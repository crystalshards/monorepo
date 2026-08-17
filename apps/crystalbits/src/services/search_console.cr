require "http/client"
require "json"
require "uri"

module CrystalBits
  # What a reader typed into Google before they arrived here, pulled into our
  # own database once a day.
  #
  # Our own request log can say which pages were read; it cannot say which
  # query brought the reader, how often Google showed the page, or where it
  # ranked. Search Console holds that half of the story, and this service is
  # the whole integration: one claimed, bounded fetch per pass, upserted into
  # search_console_daily, so the stats page renders from our tables and never
  # talks to Google.
  #
  # Three properties drive every decision in here, in this order.
  #
  # 1. The page must be able to tell "no data" apart from "no traffic". A day
  #    with genuinely zero impressions and a day we could not fetch are
  #    different facts, and they never land in the database the same way:
  #    a fetched day with no rows still advances covered_through, a failed
  #    day never does, and last_error says why. Whatever this service returns
  #    is what the page renders, so every failure mode is a distinct state,
  #    not an empty result.
  # 2. Google's numbers for a day are revised while the day is recent. A
  #    fetch writes with an upsert and the trailing unsettled days are
  #    refetched on every pass, so a premature answer is corrected by the
  #    next one instead of frozen. covered_through only ever advances over a
  #    day old enough to be final, which is what makes "settled" and
  #    "preliminary" distinguishable to a reader.
  # 3. A pass is claimed and bounded like every other periodic job here.
  #    The claim is a row in stats_rollups under the name "search_console",
  #    won with one UPDATE ... RETURNING, so two renders at once start
  #    exactly one fetch and a render inside the floor starts none. A pass
  #    fetches at most MAX_DAYS_PER_PASS days, walking forward from
  #    covered_through, so a gap from a deploy or an outage heals pass by
  #    pass with no backfill mechanism and no day is ever skipped.
  #
  # Authentication is the ambient Cloud Run identity, read from the metadata
  # server by GoogleMetadata exactly the way the docs build queue already
  # does it: there is no key file and no static credential anywhere in this
  # path. The one piece of configuration is SEARCH_CONSOLE_PROPERTY, the
  # property this site is registered as (a domain property like
  # "sc-domain:example.org" or a URL prefix like "https://example.org/").
  # It stays optional on purpose: before a human adds this site's service
  # account to the property in Search Console there is nothing to fetch, and
  # the honest state is "not configured", not a boot failure and not an
  # empty chart.
  module SearchConsole
    # The stats_rollups row this job claims under. Shared table, one row per
    # periodic job, so the rollup job's row and this one never collide.
    CLAIM_NAME = "search_console"

    # How soon a second pass may claim the job after the last claim. An hour
    # is long enough that a busy stats page costs Google almost nothing and
    # short enough that a failure is retried the same day. The daily cadence
    # itself comes from covered_through advancing one settled day per pass,
    # not from this floor.
    FETCH_FLOOR = 1.hour

    # The most days one pass will fetch. Bounds what a catching-up pass costs
    # the reader who triggered it. A longer gap heals three days per pass.
    MAX_DAYS_PER_PASS = 3

    # A day newer than this is still being revised by Google: fetched and
    # stored (the upsert corrects it on later passes) but never counted in
    # covered_through. A day at least this old is treated as final. Three
    # days because Search Console's own documentation says recent data can
    # change for a couple of days; a day we call settled must not be one
    # Google is still rewriting.
    SETTLED_LAG = 3.days

    # The API's per-request maximum. A day with more distinct (query, page)
    # rows than this is so far outside this product's traffic that paging is
    # not built; if it ever matters, the API pages with startRow.
    ROW_LIMIT = 25_000

    # Per-request budget. A full pass is at most MAX_DAYS_PER_PASS requests,
    # and only the reader who wins the claim pays it: everyone else inside
    # the floor renders from what is already stored.
    CONNECT_TIMEOUT = 3.seconds
    WRITE_TIMEOUT   = 3.seconds
    READ_TIMEOUT    = 10.seconds

    API_ORIGIN = "https://searchconsole.googleapis.com"

    # The credential this job runs as: a token from the metadata server and
    # the email of the service account it belongs to. The email travels with
    # the token because a 403 message has to name the account a human must
    # grant, and "the service account" is not a name.
    record Identity, token : String, account_email : String

    # One call to the Search Console API, abstracted so specs script answers
    # instead of sockets. The transport sees the exact URL and body that
    # would go to Google; the service sees exactly the status and body that
    # would come back.
    record Request, url : String, token : String, body : String
    record Response, status : Int32, body : String

    alias Transport = Proc(Request, Response)
    alias IdentityProvider = Proc(Identity)

    # What a refresh attempt did. The page renders from these distinctions,
    # so they are an enum, not a log line.
    #
    #   Disabled  no SEARCH_CONSOLE_PROPERTY: the feature is off
    #   Skipped   another caller claimed the job inside FETCH_FLOOR
    #   Current   claimed, but nothing is owed past covered_through
    #   Stored    claimed and stored rows; rows_stored may be zero for a
    #             pass over days with no impressions, which is a success
    #   Failed    claimed and hit an error; error names what and, for an
    #             access problem, who
    enum Outcome
      Disabled
      Skipped
      Current
      Stored
      Failed
    end

    record Result, outcome : Outcome, days_stored : Int32 = 0, rows_stored : Int32 = 0, error : String? = nil

    # What the page needs to render the section honestly. covered_through is
    # the newest day whose numbers are final; days newer than it with rows
    # are preliminary, days newer than it without rows are unknown, never
    # zero. last_error is the last pass's failure verbatim, nil after any
    # pass that completed, so "stale but explained" and "broken" are not the
    # same render.
    record Status, configured : Bool, property : String?, covered_through : Time?, last_error : String? do
      def configured? : Bool
        configured
      end

      # Configured but no pass has completed yet and none has failed: the
      # state a brand new deployment is in. Distinct from both "no traffic"
      # and "broken".
      def pending? : Bool
        configured && covered_through.nil? && last_error.nil?
      end

      def failing? : Bool
        !last_error.nil?
      end
    end

    # The account this site runs as has not been granted the property. This
    # is a specific, fixable, human problem, and the message names both sides
    # of the grant that is missing rather than reading as empty data.
    class AccessDenied < Exception
      getter account_email : String
      getter property : String

      def initialize(@account_email : String, @property : String, detail : String)
        super(
          "Google Search Console answered 403 Forbidden for property " \
          "#{property}: the service account #{account_email} is not a user " \
          "of that property. Add #{account_email} under Settings, Users and " \
          "permissions, in Search Console for #{property}. Until a human " \
          "does that, this site's search data is missing, not zero. " \
          "Google said: #{detail}"
        )
      end
    end

    # The API answered but not with rows: a 5xx, a 401, a 429, an
    # unparseable 200. Distinct from AccessDenied because the fix is
    # different: nothing a human does to the property helps.
    class ApiError < Exception
    end

    # Wins the right to run a pass. One statement: the UPDATE returns a row
    # only to the caller whose claim actually landed, so "did I win" and "is
    # the row now claimed" cannot disagree under two renders at once.
    CLAIM_SQL = <<-SQL
      UPDATE stats_rollups
      SET claimed_at = $2
      WHERE name = $1
        AND (claimed_at IS NULL OR claimed_at <= $3)
      RETURNING name
      SQL

    ENSURE_CLAIM_ROW_SQL = <<-SQL
      INSERT INTO stats_rollups (name)
      VALUES ($1)
      ON CONFLICT (name) DO NOTHING
      SQL

    # Replaces a day's numbers rather than adding to them. This is what
    # makes refetching a recent day safe: Google's revision lands as an
    # update, and the row count for the day never grows.
    UPSERT_SQL = <<-SQL
      INSERT INTO search_console_daily (day, query, page, clicks, impressions, position)
      VALUES ($1::date, $2, $3, $4, $5, $6)
      ON CONFLICT (day, query, page) DO UPDATE
      SET clicks = EXCLUDED.clicks,
          impressions = EXCLUDED.impressions,
          position = EXCLUDED.position
      SQL

    ADVANCE_COVERAGE_SQL = <<-SQL
      UPDATE stats_rollups
      SET covered_through = $2::date
      WHERE name = $1
      SQL

    RECORD_ERROR_SQL = <<-SQL
      UPDATE stats_rollups
      SET last_error = $2
      WHERE name = $1
      SQL

    CLEAR_ERROR_SQL = <<-SQL
      UPDATE stats_rollups
      SET last_error = NULL
      WHERE name = $1
      SQL

    STATUS_SQL = <<-SQL
      SELECT covered_through, last_error
      FROM stats_rollups
      WHERE name = $1
      SQL

    @@transport : Transport?
    @@identity : IdentityProvider?
    @@clock : Proc(Time)?
    @@property : String?

    # Test seams, mirroring BitsFeed.transport=: nil restores the real thing.
    def self.transport=(transport : Transport?)
      @@transport = transport
    end

    def self.identity=(identity : IdentityProvider?)
      @@identity = identity
    end

    def self.clock=(clock : Proc(Time)?)
      @@clock = clock
    end

    # Writable so a spec can point the job at a stub property, or at "" for
    # the not-configured state, without reaching into the process
    # environment. nil restores SEARCH_CONSOLE_PROPERTY.
    def self.property=(property : String?)
      @@property = property
    end

    # The property this site fetches, or nil when the feature is off.
    def self.property : String?
      if override = @@property
        return override.presence
      end

      ENV["SEARCH_CONSOLE_PROPERTY"]?.presence
    end

    # Fetch and store whatever is owed. Safe to call on every stats page
    # render: the claim decides whether a pass actually runs.
    def self.refresh : Result
      property = self.property
      return Result.new(Outcome::Disabled) unless property

      now = clock.call
      return Result.new(Outcome::Skipped) unless claim(now)

      perform(property, now)
    end

    # What the page renders. Reads only our own tables; never touches the
    # network, so it is safe to call on every render regardless of state.
    def self.status : Status
      property = self.property
      return Status.new(configured: false, property: nil, covered_through: nil, last_error: nil) unless property

      row = AppDatabase.query_one?(STATUS_SQL, CLAIM_NAME, as: {Time?, String?})
      Status.new(
        configured: true,
        property: property,
        covered_through: row.try(&.[0]),
        last_error: row.try(&.[1]),
      )
    end

    private def self.perform(property : String, now : Time) : Result
      # Initialized before the begin, so the rescue can report honest
      # partial progress with a definite type rather than a second error.
      days_stored = 0
      rows_stored = 0

      begin
        today = day_floor(now)
        last = today - 1.day

        # The day after the newest settled one, or the trailing window on
        # the first pass ever. Starting anywhere else would either skip
        # days, leaving holes that render exactly like zero-impression days,
        # or refetch history that is already final.
        first = covered_through.try(&.+(1.day)) || today - MAX_DAYS_PER_PASS.days

        if first > last
          AppDatabase.exec(CLEAR_ERROR_SQL, CLAIM_NAME)
          return Result.new(Outcome::Current)
        end

        owed = [] of Time
        day = first
        while day <= last && owed.size < MAX_DAYS_PER_PASS
          owed << day
          day += 1.day
        end

        identity = fetch_identity

        owed.each do |owed_day|
          response = query_day(identity, property, owed_day)
          rows = parse_rows(response.body)

          # One transaction per day: a day is stored whole or not at all, so
          # a failure partway through a day can never leave half of it
          # looking like the whole of it. Days already committed stay
          # committed, which is exactly what "a partial failure keeps prior
          # rows" means here.
          AppDatabase.transaction do
            rows.each do |row|
              AppDatabase.exec(UPSERT_SQL, row.day, row.query, row.page, row.clicks, row.impressions, row.position)
            end

            if settled?(owed_day, today)
              AppDatabase.exec(ADVANCE_COVERAGE_SQL, CLAIM_NAME, day_string(owed_day))
            end
          end

          days_stored += 1
          rows_stored += rows.size
        end

        AppDatabase.exec(CLEAR_ERROR_SQL, CLAIM_NAME)
        Log.for("search_console").info { "stored #{rows_stored} rows across #{days_stored} days for #{property}" }
        Result.new(Outcome::Stored, days_stored: days_stored, rows_stored: rows_stored)
      rescue ex : Exception
        # Broad on purpose, and this is the only rescue on the path. This
        # runs inside somebody's page render: a bug here, a dead metadata
        # server, a dropped socket or a rejected statement must cost the
        # refresh and nothing else. The message goes to last_error so the
        # page shows "broken, and here is why, with data through X" rather
        # than a 500.
        message = "#{ex.class}: #{ex.message}"
        Log.for("search_console").warn { "refresh failed for #{property}: #{message}" }
        AppDatabase.exec(RECORD_ERROR_SQL, CLAIM_NAME, message)
        Result.new(Outcome::Failed, days_stored: days_stored, rows_stored: rows_stored, error: message)
      end
    end

    private def self.claim(now : Time) : Bool
      AppDatabase.exec(ENSURE_CLAIM_ROW_SQL, CLAIM_NAME)
      !!AppDatabase.query_all(CLAIM_SQL, CLAIM_NAME, now, now - FETCH_FLOOR, as: String).first?
    end

    # The newest settled day, straight from the claim row. pg decodes a date
    # as midnight UTC, which is the same clock day_floor keeps, so the
    # comparisons in perform compare days to days.
    private def self.covered_through : Time?
      AppDatabase.query_one?(READ_COVERAGE_SQL, CLAIM_NAME, as: Time?)
    end

    READ_COVERAGE_SQL = <<-SQL
      SELECT covered_through
      FROM stats_rollups
      WHERE name = $1
      SQL

    private def self.query_day(identity : Identity, property : String, day : Time) : Response
      url = "#{API_ORIGIN}/v1/sites/#{URI.encode_www_form(property)}/searchanalytics/query"
      body = {
        # dataState "all" includes the days Google is still finalizing.
        # Without it a recent day answers as empty, which is the
        # missing-reads-as-zero confusion this service exists to prevent;
        # the refetch window corrects the number as it settles.
        startDate:  day_string(day),
        endDate:    day_string(day),
        dimensions: ["date", "query", "page"],
        dataState:  "all",
        rowLimit:   ROW_LIMIT,
      }.to_json

      response = transport.call(Request.new(url: url, token: identity.token, body: body))

      case response.status
      when 200
        response
      when 403
        raise AccessDenied.new(identity.account_email, property, response.body)
      else
        raise ApiError.new(
          "Search Console answered HTTP #{response.status} for property " \
          "#{property} on #{day_string(day)}: #{response.body[0, 300]}"
        )
      end
    end

    # One stored row. `day` stays a string in %F form end to end: it is
    # written with a ::date cast, and never needs to be a Time in this
    # process at all.
    private record Row, day : String, query : String, page : String, clicks : Int64, impressions : Int64, position : Float64

    private def self.parse_rows(body : String) : Array(Row)
      parsed = JSON.parse(body)
      raw_rows = parsed["rows"]?
      # No "rows" key is a real answer: nothing was shown for that day. It
      # stores nothing and the day still advances coverage if settled, which
      # is what separates "zero impressions" from "never fetched".
      return [] of Row unless raw_rows

      raw_rows.as_a.map do |raw|
        keys = raw["keys"].as_a
        day = keys[0].as_s
        unless /^\d{4}-\d{2}-\d{2}$/.matches?(day)
          raise ApiError.new("Search Console row carried an unparseable day: #{day.inspect}")
        end

        position = raw["position"]
        Row.new(
          day: day,
          query: keys[1].as_s,
          page: keys[2].as_s,
          clicks: raw["clicks"].as_i64,
          impressions: raw["impressions"].as_i64,
          # Google sends a float, but a whole number may serialize as an
          # integer; accept either rather than failing the day over JSON
          # arithmetic.
          position: position.as_f? || position.as_i64.to_f,
        )
      end
    rescue ex : JSON::Error | KeyError | IndexError | TypeCastError
      raise ApiError.new("Search Console answered 200 with a body that is not rows: #{ex.message}")
    end

    private def self.settled?(day : Time, today : Time) : Bool
      day <= today - SETTLED_LAG
    end

    private def self.day_floor(time : Time) : Time
      utc = time.in(Time::Location::UTC)
      Time.utc(utc.year, utc.month, utc.day)
    end

    private def self.day_string(day : Time) : String
      day.to_s("%F")
    end

    private def self.transport : Transport
      @@transport || ->(request : Request) { default_transport(request) }
    end

    private def self.fetch_identity : Identity
      provider = @@identity || -> { Identity.new(GoogleMetadata.access_token, GoogleMetadata.service_account_email) }
      provider.call
    end

    private def self.clock : Proc(Time)
      @@clock || -> { Time.utc }
    end

    private def self.default_transport(request : Request) : Response
      uri = URI.parse(request.url)
      client = HTTP::Client.new(uri)
      client.connect_timeout = CONNECT_TIMEOUT
      client.write_timeout = WRITE_TIMEOUT
      client.read_timeout = READ_TIMEOUT

      begin
        response = client.post(
          uri.request_target,
          headers: HTTP::Headers{
            "Authorization" => "Bearer #{request.token}",
            "Content-Type"  => "application/json",
          },
          body: request.body,
        )
        Response.new(status: response.status_code, body: response.body)
      ensure
        client.close
      end
    end
  end
end
