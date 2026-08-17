# First party stats: rolls the raw page_views table into per-day rows in
# daily_stats, lazily, on the first read that notices a day is missing, and
# answers every question the public stats page asks.
#
# WHY LAZY. The raw rows are already in this database, so the rollup is one
# aggregate query away at all times. A scheduled job would need its own
# Cloud Run service, its own terraform and its own failure handling to save
# a query that runs in milliseconds once a day. The first reader of the
# morning pays it instead, and the stats_rollups claim row makes sure only
# one reader ever does.
#
# THE CLAIM. `ensure_fresh` claims the 'daily_stats' row of stats_rollups
# the same way ShardIndexRequests claims a shard: an UPDATE whose WHERE
# clause is the eligibility test, with RETURNING making "did I win" and "is
# the row now claimed" the same question. Two conditions gate the claim: the
# previous claim must be older than RETRY_FLOOR, so a failed pass is
# retried but never hammered, and covered_through must trail yesterday, so
# a fresh rollup is never redone. The pass itself runs bounded
# (rollup_timeout), because a reader's page load cannot hang on it; a loser
# of the claim never waits on the winner at all.
#
# WHY NEVER TODAY. Today is still accumulating. Writing a partial day as a
# final row would be wrong forever, because a covered day is never
# recomputed. Only days that have fully ended are rolled, and covered_days
# advance to yesterday at most.
#
# WHY SQL. A month of raw views is the wrong thing to load into a web
# process, so the aggregation runs in the database as INSERT ... SELECT
# with the upsert keyed on the grain. The same pass advances the claim row
# and prunes page_views past RETENTION, all in one transaction: any failure
# leaves every piece of it unwritten, and retention needs no second
# mechanism.
#
# THE 'site' GRAIN. Besides the full (day, path_kind, path, referrer_host,
# country) grain, each rolled day gets one row with path_kind 'site' and
# empty dimensions, whose visitors is an exact COUNT(DISTINCT visitor_hash)
# over the whole day. Summing visitors across path rows counts a person who
# read two pages twice, so per-day totals come from these rows only. The
# full grain answers breakdowns; the site row answers totals.
#
# WHAT THE NUMBERS MEAN. A single day is exact: visitors is distinct salted
# hashes that day. A range's views are an exact sum, but a range's visitors
# are a sum of per-day distinct counts, because the raw hashes are pruned
# after RETENTION and a range-unique count is then unrecoverable. The page
# labels accordingly; both are stated on every method below.
module CrystalGigs::Stats
  # The stats_rollups row this service claims. One per app database, named
  # after what the pass produces.
  NAME = "daily_stats"

  # How long a claim is left alone before a later request may retry it.
  # Measured from claimed_at, which is stamped before the pass runs, so this
  # also bounds how long a pass whose fiber never reported back looks
  # claimed. Ten minutes is far beyond the milliseconds the pass needs and
  # short enough that a broken morning is retried the same morning.
  RETRY_FLOOR = 10.minutes

  # Raw views are kept this long. The same pass that aggregates also prunes,
  # so a day older than this window exists only as daily_stats rows.
  RETENTION = 30.days

  # Backstop for each statement of the pass, so a pass abandoned by
  # rollup_timeout cannot hold its row locks open ended. Per statement, not
  # per pass: Postgres offers no per-transaction budget, and the reader side
  # bound is what a reader ever waits on.
  STATEMENT_BUDGET = 10.seconds

  # How long a winning claim may spend on the pass before the reader stops
  # waiting and renders what is already rolled. A class_property, not a
  # constant, so a spec can shrink it to prove the timeout path without a
  # real wait. Set just above STATEMENT_BUDGET so a database side timeout
  # lands as a recorded failure rather than a silent abandonment.
  class_property rollup_timeout : Time::Span = 12.seconds

  # Test seam. Every pass runs through this proc, which defaults to the real
  # one so production is unchanged when nothing installs a fake. Specs swap
  # it to force a failure or a pass slow enough to trip rollup_timeout, and
  # must restore it in an `ensure`.
  class_property runner : Proc(Bool) = -> { run_pass; true }

  # One day of whole site traffic. `day` is a UTC midnight; `visitors` is
  # exact for the day.
  struct DayTotal
    getter day : Time
    getter views : Int64
    getter visitors : Int64

    def initialize(@day : Time, @views : Int64, @visitors : Int64)
    end
  end

  # One path's traffic over a range. `visitors` is a sum of per-day distinct
  # counts (see the module comment), never a range-unique count.
  struct PathStat
    getter path : String
    getter views : Int64
    getter visitors : Int64

    def initialize(@path : String, @views : Int64, @visitors : Int64)
    end
  end

  # One referrer host's traffic over a range. 'direct' is the no-referrer
  # bucket. Same visitors semantics as PathStat.
  struct ReferrerStat
    getter referrer_host : String
    getter views : Int64
    getter visitors : Int64

    def initialize(@referrer_host : String, @views : Int64, @visitors : Int64)
    end
  end

  # One country's traffic over a range. 'unknown' is the no-geo-header
  # bucket. Same visitors semantics as PathStat.
  struct CountryStat
    getter country : String
    getter views : Int64
    getter visitors : Int64

    def initialize(@country : String, @views : Int64, @visitors : Int64)
    end
  end

  # The claim reuses the shape ShardIndexRequests proves: the WHERE clause
  # is the whole eligibility test and RETURNING answers "did I win" with
  # the row actually touched, so two readers rendering at the same moment
  # cannot both believe they claimed the pass.
  #
  # last_error clears on a winning claim, matching ShardIndexer's own: a new
  # pass is about to learn a fresh answer and the old failure would be stale
  # the moment it starts.
  CLAIM_SQL = <<-SQL
    UPDATE stats_rollups
    SET claimed_at = $2,
        last_error = NULL
    WHERE name = $1
      AND (claimed_at IS NULL OR claimed_at <= $3)
      AND (covered_through IS NULL OR covered_through < $4::date)
    RETURNING name
    SQL

  SEED_SQL = <<-SQL
    INSERT INTO stats_rollups (name) VALUES ($1)
    ON CONFLICT (name) DO NOTHING
    SQL

  COVERED_SQL = <<-SQL
    SELECT covered_through FROM stats_rollups WHERE name = $1
    SQL

  # The first pass ever has no covered_through to resume from, so it starts
  # at the oldest raw row present. AT TIME ZONE 'UTC' fixes the day
  # boundary the same way the rollup does, whatever the session TimeZone.
  EARLIEST_SQL = <<-SQL
    SELECT (MIN(occurred_at) AT TIME ZONE 'UTC')::date FROM page_views
    SQL

  # Recomputes each ended day in [since, until) from raw rows and upserts
  # against the grain, so re-rolling a day overwrites rather than double
  # counts. Days are UTC: occurred_at is shifted with AT TIME ZONE 'UTC'
  # before the date is taken, and the range bounds are UTC midnights, so
  # neither depends on the session TimeZone.
  ROLLUP_SQL = <<-SQL
    INSERT INTO daily_stats (day, path_kind, path, referrer_host, country, views, visitors)
    SELECT (occurred_at AT TIME ZONE 'UTC')::date,
           path_kind,
           path,
           COALESCE(referrer_host, 'direct'),
           COALESCE(country, 'unknown'),
           COUNT(*),
           COUNT(DISTINCT visitor_hash)
    FROM page_views
    WHERE occurred_at >= ($1 || ' 00:00:00+00')::timestamptz
      AND occurred_at <  ($2 || ' 00:00:00+00')::timestamptz
    GROUP BY 1, 2, 3, 4, 5
    ON CONFLICT (day, path_kind, path, referrer_host, country)
    DO UPDATE SET views = EXCLUDED.views,
                  visitors = EXCLUDED.visitors,
                  updated_at = NOW()
    SQL

  # The whole-day row per day, so per-day totals never sum overlapping
  # grains. Empty dimensions keep it out of every breakdown query, which
  # filter on a real path_kind, host or country.
  SITE_ROLLUP_SQL = <<-SQL
    INSERT INTO daily_stats (day, path_kind, path, referrer_host, country, views, visitors)
    SELECT (occurred_at AT TIME ZONE 'UTC')::date,
           'site', '', '', '',
           COUNT(*),
           COUNT(DISTINCT visitor_hash)
    FROM page_views
    WHERE occurred_at >= ($1 || ' 00:00:00+00')::timestamptz
      AND occurred_at <  ($2 || ' 00:00:00+00')::timestamptz
    GROUP BY 1
    ON CONFLICT (day, path_kind, path, referrer_host, country)
    DO UPDATE SET views = EXCLUDED.views,
                  visitors = EXCLUDED.visitors,
                  updated_at = NOW()
    SQL

  ADVANCE_SQL = <<-SQL
    UPDATE stats_rollups SET covered_through = $2::date WHERE name = $1
    SQL

  PRUNE_SQL = <<-SQL
    DELETE FROM page_views WHERE occurred_at < $1
    SQL

  FAIL_SQL = <<-SQL
    UPDATE stats_rollups SET last_error = $2 WHERE name = $1
    SQL

  # One row per day in the range, zero filled, from the 'site' grain only.
  # generate_series on the two dates is what fills a no-traffic day with a
  # real zero instead of a gap the page would have to invent.
  DAILY_TOTALS_SQL = <<-SQL
    SELECT series.day::date AS day,
           COALESCE(s.views, 0) AS views,
           COALESCE(s.visitors, 0) AS visitors
    FROM generate_series($1::date, $2::date, '1 day'::interval) AS series(day)
    LEFT JOIN daily_stats s ON s.day = series.day AND s.path_kind = 'site'
    ORDER BY series.day
    SQL

  TOP_PATHS_SQL = <<-SQL
    SELECT path, SUM(views)::bigint AS views, SUM(visitors)::bigint AS visitors
    FROM daily_stats
    WHERE path_kind = ANY($1)
      AND day >= $2::date
      AND day <= $3::date
    GROUP BY path
    ORDER BY views DESC, path
    LIMIT $4
    SQL

  # 'site' rows carry whole-day totals, not a real host or country, so the
  # breakdowns exclude them explicitly rather than letting one day's totals
  # rank as the top referrer.
  TOP_REFERRERS_SQL = <<-SQL
    SELECT referrer_host, SUM(views)::bigint AS views, SUM(visitors)::bigint AS visitors
    FROM daily_stats
    WHERE path_kind <> 'site'
      AND day >= $1::date
      AND day <= $2::date
    GROUP BY referrer_host
    ORDER BY views DESC, referrer_host
    LIMIT $3
    SQL

  TOP_COUNTRIES_SQL = <<-SQL
    SELECT country, SUM(views)::bigint AS views, SUM(visitors)::bigint AS visitors
    FROM daily_stats
    WHERE path_kind <> 'site'
      AND day >= $1::date
      AND day <= $2::date
    GROUP BY country
    ORDER BY views DESC, country
    LIMIT $3
    SQL

  # Claims and runs the rollup if any ended day is not yet rolled. Safe to
  # call on every page render: an already-fresh rollup claims nothing and
  # does nothing, a claim lost to a concurrent reader does not wait, and any
  # failure answers false rather than breaking the render. True means
  # daily_stats now covers every day through yesterday; false means the
  # page should render what is already rolled and say so.
  # Test seam, the same shape as PageViews.async_writes. A page spec plants
  # the exact rollup state it wants to see rendered, and a real pass mid
  # request would overwrite it: the pass would find nothing pending in an
  # empty page_views, mark the claim covered through yesterday, and clear the
  # very last_error the spec planted to prove the page states a lag. Left on
  # by default so production and the rollup's own specs are unchanged; a page
  # spec turns it off and restores it in an ensure.
  class_property lazy_rollup : Bool = true

  def self.ensure_fresh : Bool
    return true unless @@lazy_rollup

    now = Time.utc
    # Already covering through yesterday: nothing to claim. Work pending but
    # the claim refused (a concurrent winner, or a failure inside the retry
    # floor): the numbers are stale and the honest answer is false.
    return true unless work_pending?(now)
    return false unless claimed?(now)
    run_bounded
  rescue ex : Exception
    # Whatever failed here, the render must not: yesterday's rows are still
    # the honest thing to show.
    Log.error(exception: ex) { "Could not check stats freshness" }
    false
  end

  # Whole-site views and visitors for each day of the inclusive range,
  # zero filled for days with no traffic. Exact per day, from the 'site'
  # grain; the time of day of `from` and `to` is discarded.
  def self.daily_totals(from : Time, to : Time) : Array(DayTotal)
    AppDatabase.query_all(DAILY_TOTALS_SQL, day_string(from), day_string(to), as: {Time, Int64, Int64}).map do |(day, views, visitors)|
      DayTotal.new(day: day, views: views, visitors: visitors)
    end
  end

  # The most viewed paths of one path_kind over the inclusive range, most
  # views first, ties by path so the order is stable. Visitors are summed
  # per-day distinct counts, not a range-unique count.
  def self.top_paths(path_kind : String, from : Time, to : Time, limit : Int32 = 10) : Array(PathStat)
    top_paths([path_kind], from, to, limit)
  end

  # The same ranking over several kinds taken together, for a page that
  # reads e.g. doc versions and doc types as one list.
  def self.top_paths(path_kinds : Array(String), from : Time, to : Time, limit : Int32 = 10) : Array(PathStat)
    AppDatabase.query_all(TOP_PATHS_SQL, path_kinds, day_string(from), day_string(to), limit, as: {String, Int64, Int64}).map do |(path, views, visitors)|
      PathStat.new(path: path, views: views, visitors: visitors)
    end
  end

  # The referrer hosts sending the most views over the inclusive range,
  # 'direct' included as its own bucket. Same visitors semantics as
  # top_paths.
  def self.top_referrers(from : Time, to : Time, limit : Int32 = 10) : Array(ReferrerStat)
    AppDatabase.query_all(TOP_REFERRERS_SQL, day_string(from), day_string(to), limit, as: {String, Int64, Int64}).map do |(host, views, visitors)|
      ReferrerStat.new(referrer_host: host, views: views, visitors: visitors)
    end
  end

  # The countries sending the most views over the inclusive range, with
  # 'unknown' for views whose geo header was absent. Same visitors semantics
  # as top_paths.
  def self.top_countries(from : Time, to : Time, limit : Int32 = 20) : Array(CountryStat)
    AppDatabase.query_all(TOP_COUNTRIES_SQL, day_string(from), day_string(to), limit, as: {String, Int64, Int64}).map do |(country, views, visitors)|
      CountryStat.new(country: country, views: views, visitors: visitors)
    end
  end

  # The same length window immediately before the given one, so the page
  # can put this period's number next to last period's without inventing a
  # trend. Days, like every range here: the time of day is discarded.
  def self.previous_period(from : Time, to : Time) : NamedTuple(from: Time, to: Time)
    first = day_start(from)
    last = day_start(to)
    previous_last = first - 1.day
    {from: previous_last - (last - first).days.days, to: previous_last}
  end

  # The newest day the rollup has finalized, or nil before the first pass.
  # The page prints this as "numbers through <day>" so a half-rolled day
  # never reads as a dip.
  def self.covered_through : Time?
    AppDatabase.query_one?(COVERED_SQL, NAME, as: Time?)
  end

  # A day is pending when covered_through trails yesterday, or when no pass
  # has ever completed (no row yet, or a row no pass has advanced). The
  # claim itself re-tests the same condition atomically, so two readers
  # that both see pending work still produce exactly one pass.
  private def self.work_pending?(now : Time) : Bool
    covered = AppDatabase.query_one?(COVERED_SQL, NAME, as: Time?)
    covered.nil? || covered < day_start(now - 1.day)
  end

  private def self.claimed?(now : Time) : Bool
    yesterday = day_string(now - 1.day)
    AppDatabase.exec(SEED_SQL, NAME)
    AppDatabase.query_all(CLAIM_SQL, NAME, now, now - RETRY_FLOOR, yesterday, as: String).any?
  end

  # Runs the pass with a bound, so a reader's render cannot hang on it.
  # select over a Channel rather than a bare call because Crystal has no way
  # to interrupt a fiber mid-flight: a pass that outlives rollup_timeout
  # keeps running in the background, which is safe because the pass is
  # idempotent, and STATEMENT_BUDGET keeps its transaction from holding
  # locks open ended. The claim row keeps claimed_at in both outcomes, so a
  # timed out or failed pass is reclaimable once RETRY_FLOOR has passed.
  private def self.run_bounded : Bool
    done = Channel(Bool).new(1)

    spawn do
      begin
        fresh = @@runner.call
        done.send(fresh)
      rescue ex : Exception
        # One pass raising must read as a failed pass, not a crashed
        # render. The failure goes on the claim row in its own statement,
        # because the pass's transaction has already rolled back.
        record_failure(ex)
        Log.error(exception: ex) { "Stats rollup pass failed" }
        done.send(false)
      end
    end

    select
    when fresh = done.receive
      fresh
    when timeout(@@rollup_timeout)
      Log.warn { "Stats rollup exceeded #{@@rollup_timeout}; rendering what is already rolled" }
      false
    end
  end

  # The pass itself: aggregate every ended-but-uncovered day, advance the
  # claim row and prune raw views, as one transaction so a failure anywhere
  # leaves none of it written. Runs inside the runner seam; call
  # ensure_fresh, not this.
  def self.run_pass : Nil
    now = Time.utc
    today = day_string(now)
    since = begin
      if covered = AppDatabase.query_one?(COVERED_SQL, NAME, as: Time?)
        day_string(covered + 1.day)
      else
        earliest_day || today
      end
    end

    AppDatabase.transaction do
      AppDatabase.exec("SET LOCAL statement_timeout = #{STATEMENT_BUDGET.total_milliseconds.to_i}")
      AppDatabase.exec(ROLLUP_SQL, since, today)
      AppDatabase.exec(SITE_ROLLUP_SQL, since, today)
      AppDatabase.exec(ADVANCE_SQL, NAME, day_string(now - 1.day))
      AppDatabase.exec(PRUNE_SQL, now - RETENTION)
    end
  end

  private def self.record_failure(ex : Exception) : Nil
    AppDatabase.exec(FAIL_SQL, NAME, (ex.message || ex.class.name)[0, 500])
  rescue
    # Best effort: if the database is the thing that failed, recording the
    # failure there fails too, and the original exception is the one worth
    # keeping.
  end

  private def self.earliest_day : String?
    AppDatabase.query_one(EARLIEST_SQL, as: Time?).try { |day| day_string(day) }
  end

  private def self.day_start(time : Time) : Time
    utc = time.to_utc
    Time.utc(utc.year, utc.month, utc.day)
  end

  private def self.day_string(time : Time) : String
    day_start(time).to_s("%F")
  end
end
