require "json"
require "base64"
require "./base_crawler"

module Discovery
  # Finds shards on GitHub by looking for the file that makes a repository a
  # shard, rather than for the language label.
  #
  # The query is code search for `filename:shard.yml path:/`, so a repository is
  # a candidate because it has a shard.yml at its root. Enumerating
  # `language:Crystal` instead would be cheaper and wrong: the label is derived
  # from file contents by GitHub and is absent or wrong on plenty of real shards,
  # and it also sweeps in thousands of Crystal repositories that are applications
  # rather than shards. Code search requires authentication, which is one of the
  # reasons a token is mandatory.
  #
  # The 1000-result cap is the hard part. Any single GitHub search returns at
  # most 1000 items no matter how many matched, so a query that matches more than
  # that silently truncates. The sweep therefore partitions the search by file
  # size, which is disjoint and total (every shard.yml has exactly one size), and
  # splits any window whose total_count exceeds the cap until each window fits.
  class GithubCrawler < BaseCrawler
    HOST = "github.com"

    # GitHub returns at most this many results per query however many matched.
    RESULT_CAP = 1000
    PER_PAGE   =  100

    # Upper bound of the first size window. shard.yml files run from a few dozen
    # bytes to a few kilobytes; anything above this is swept by the open-ended
    # window so nothing is excluded by the choice.
    INITIAL_MAX_SIZE = 4096

    def initialize(
      base_url : String? = nil,
      token : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
      max_pages : Int32? = nil,
    )
      super(host: HOST, base_url: base_url, token: token, sleeper: sleeper, max_pages: max_pages)
    end

    def default_base_url : String
      "https://api.github.com"
    end

    def auth_headers(token : String?) : HTTP::Headers
      headers = HTTP::Headers{
        "Accept"               => "application/vnd.github+json",
        "X-GitHub-Api-Version" => "2022-11-28",
      }
      headers["Authorization"] = "Bearer #{token}" if token
      headers
    end

    # Whether this sweep partitioned the host finely enough that every root
    # shard.yml was reachable.
    #
    # Normally true: the size partition is disjoint and total, so every file is
    # in exactly one window. It becomes false when a window could not be narrowed
    # below GitHub's 1000-result cap, which happens if more than 1000 root
    # shard.yml files share one exact byte size. Then those results really are
    # truncated, and the sweep says so instead of reporting a complete view of a
    # host it did not finish seeing.
    #
    # The other caveat, stated rather than hidden: this reads GitHub's code
    # search index, so a repository GitHub has not indexed is invisible to any
    # query we could write.
    getter? truncated : Bool = false

    def exhaustive? : Bool
      !truncated?
    end

    # The only way a GitHub sweep falls short is a window it could not narrow
    # below the result cap.
    def coverage_reason : String
      CrawlState::StopReason::RESULT_CAP_TRUNCATED
    end

    def fetch_page(cursor : String?) : CrawlPage
      position = Position.load(cursor)
      return CrawlPage.new([] of DiscoveredRepository, nil) if position.finished?

      window = position.current
      response = search(window, position.page)
      total = response["total_count"]?.try(&.as_i?) || 0

      # More matches than one query can return. Split the window and try again
      # rather than accepting the first 1000 and calling the host done.
      if position.page == 1 && total > RESULT_CAP
        if window.splittable?
          Log.info { "#{host}: size window #{window} matched #{total}, splitting" }
          return CrawlPage.new([] of DiscoveredRepository, position.split.to_cursor)
        end

        # A single byte size holding more matches than the cap cannot be narrowed
        # any further, so this window is genuinely truncated. Take what it will
        # give and record that the sweep is not a complete view of the host.
        @truncated = true
        Log.warn do
          "#{host}: size window #{window} matched #{total}, more than the #{RESULT_CAP} " \
          "result cap, and cannot be narrowed further. #{total - RESULT_CAP} results in " \
          "this window are unreachable, so this sweep is not exhaustive."
        end
      end

      items = response["items"]?.try(&.as_a?) || [] of JSON::Any
      repositories = items.compact_map { |item| to_repository(item) }

      last_page = (Math.min(total, RESULT_CAP) - 1) // PER_PAGE + 1
      next_position = if position.page >= last_page || items.empty?
                        position.advance_window
                      else
                        position.advance_page
                      end

      CrawlPage.new(repositories, next_position.to_cursor)
    end

    # Code search already told us there is a shard.yml at the root, but it is a
    # search index and can be stale, and the contents are needed anyway for the
    # shard's name. This is the authoritative check.
    def fetch_shard_yml(repository : DiscoveredRepository) : String?
      path = "/repos/#{repository.owner}/#{repository.repo}/contents/shard.yml"
      payload = client.get_json(path)

      return nil unless payload["type"]?.try(&.as_s?) == "file"

      encoded = payload["content"]?.try(&.as_s?)
      return nil unless encoded

      String.new(Base64.decode(encoded.gsub(/\s/, "")))
    rescue HostClient::NotFound
      nil
    rescue ex : Base64::Error
      Log.info { "#{repository.slug} shard.yml did not decode: #{ex.message}" }
      nil
    end

    # GitHub's code search rejects a query made only of qualifiers with 422, so
    # the query carries a literal term as well. "name" is the right one to use:
    # every shard.yml declares a name, so the term excludes nothing, and pairing
    # it with filename: and path:/ is the documented way to ask for a file by
    # name in a specific place.
    SEARCH_TERM = "name"

    private def search(window : SizeWindow, page : Int32) : JSON::Any
      query = "#{SEARCH_TERM} filename:shard.yml path:/ #{window.qualifier}"
      params = URI::Params.encode({
        "q"        => query,
        "per_page" => PER_PAGE.to_s,
        "page"     => page.to_s,
      })
      client.get_json("/search/code?#{params}")
    end

    private def to_repository(item : JSON::Any) : DiscoveredRepository?
      # Only a shard.yml at the root counts. `path:/` should guarantee it, but a
      # qualifier we rely on and a result we trust are not the same thing.
      return nil unless item["path"]?.try(&.as_s?) == "shard.yml"

      repository = item["repository"]?
      return nil unless repository

      full_name = repository["full_name"]?.try(&.as_s?)
      return nil unless full_name

      owner, _, repo = full_name.partition('/')
      return nil if owner.empty? || repo.empty?

      DiscoveredRepository.new(
        host: HOST,
        owner: owner,
        repo: repo,
        repository_url: repository["html_url"]?.try(&.as_s?) || "https://github.com/#{full_name}",
        description: repository["description"]?.try(&.as_s?),
        default_branch: repository["default_branch"]?.try(&.as_s?),
      )
    end

    # A half-open size range in bytes. `max` nil is the open-ended tail, which is
    # what makes the partition total: every file is in exactly one window.
    record SizeWindow, min : Int32, max : Int32? do
      def qualifier : String
        if limit = max
          "size:#{min}..#{limit}"
        else
          "size:>=#{min}"
        end
      end

      def splittable? : Bool
        if limit = max
          limit - min > 1
        else
          # The tail is split by capping it, which always makes progress.
          true
        end
      end

      def split : Array(SizeWindow)
        if limit = max
          middle = min + (limit - min) // 2
          [SizeWindow.new(min, middle), SizeWindow.new(middle + 1, limit)]
        else
          [SizeWindow.new(min, min * 2), SizeWindow.new(min * 2 + 1, nil)]
        end
      end

      def to_json_value : Array(Int32?)
        [min.as(Int32?), max.as(Int32?)]
      end

      def to_s(io : IO) : Nil
        io << qualifier
      end
    end

    # Where a sweep is: the window being read, the page within it, and the
    # windows still to do. Serialized as JSON into crawl_states.cursor, so a run
    # that stops anywhere picks up from the same page of the same window.
    struct Position
      getter current : SizeWindow
      getter page : Int32
      getter pending : Array(SizeWindow)
      getter? finished : Bool

      def initialize(@current : SizeWindow, @page : Int32, @pending : Array(SizeWindow), @finished : Bool = false)
      end

      def self.initial : Position
        new(
          current: SizeWindow.new(0, INITIAL_MAX_SIZE),
          page: 1,
          pending: [SizeWindow.new(INITIAL_MAX_SIZE + 1, nil)],
        )
      end

      def self.load(cursor : String?) : Position
        return initial unless cursor

        parsed = JSON.parse(cursor)
        return initial unless parsed.as_h?

        if parsed["finished"]?.try(&.as_bool?)
          return new(current: SizeWindow.new(0, 0), page: 1, pending: [] of SizeWindow, finished: true)
        end

        current = window_from(parsed["current"]?)
        return initial unless current

        pending = (parsed["pending"]?.try(&.as_a?) || [] of JSON::Any).compact_map { |value| window_from(value) }

        new(
          current: current,
          page: parsed["page"]?.try(&.as_i?) || 1,
          pending: pending,
        )
      rescue JSON::ParseException
        # A cursor we cannot read is worse than no cursor: resuming from a
        # misread position would skip pages silently. Start the host over.
        Log.warn { "Discarding unreadable github.com crawl cursor" }
        initial
      end

      private def self.window_from(value : JSON::Any?) : SizeWindow?
        array = value.try(&.as_a?)
        return nil unless array && array.size == 2

        min = array[0].as_i?
        return nil unless min

        SizeWindow.new(min, array[1].as_i?)
      end

      def advance_page : Position
        Position.new(current: current, page: page + 1, pending: pending)
      end

      def advance_window : Position
        remaining = pending.dup
        following = remaining.shift?

        if following
          Position.new(current: following, page: 1, pending: remaining)
        else
          Position.new(current: current, page: page, pending: remaining, finished: true)
        end
      end

      # Replaces the current window with its halves, keeping everything else
      # queued behind them.
      def split : Position
        halves = current.split
        Position.new(current: halves.first, page: 1, pending: halves[1..] + pending)
      end

      def to_cursor : String?
        return nil if finished?

        {
          current: current.to_json_value,
          page:    page,
          pending: pending.map(&.to_json_value),
        }.to_json
      end
    end
  end
end
