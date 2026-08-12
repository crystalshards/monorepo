require "json"
require "./base_crawler"
require "./github_api"

module Discovery
  # Seeds the registry from the top of GitHub's star ranking, so the shards
  # people have heard of are in it before the long tail is.
  #
  # WHY THIS EXISTS AT ALL.
  #
  # GithubCrawler is exhaustive and beats the 1000-result cap by partitioning
  # code search on shard.yml FILE SIZE, ascending, resuming from a cursor. That
  # partition is correct and it has a side effect nobody chose: manifest size
  # correlates with how much of a project there is. Measured on github.com,
  # `size:0..128` matches 1038 repositories and `size:129..256` another 2048, so
  # roughly three thousand of the smallest manifests are read before a 363 byte
  # one is reached. kemalcr/kemal's shard.yml is 363 bytes. The registry
  # therefore fills with test projects and hello-worlds for days while the
  # framework everyone has heard of waits behind them.
  #
  # Ascending size is not the wrong partition. Any total order over an
  # exhaustive sweep puts something last, and size is the only quantity GitHub's
  # code search will partition on. The fix is a second pass with a different
  # order, not a different order for the same pass.
  #
  # WHAT THIS PASS READS, AND WHY IT IS A DIFFERENT ENDPOINT.
  #
  # GET /search/repositories accepts `sort=stars`, which GET /search/code does
  # not. That single difference is the whole reason this class exists: ranking
  # by stars is impossible in the endpoint the exhaustive sweep is obliged to
  # use, because only code search can ask "which repositories have a shard.yml".
  #
  # Two seeds, because neither is a superset of the other. Measured live:
  # `language:Crystal` matches 10,265 repositories and `topic:crystal` matches
  # 2,224, and the second finds repositories GitHub's language detection missed
  # or mislabelled while the first finds Crystal projects nobody tagged.
  #
  # Neither seed returns shards. It returns repositories, most of which are
  # applications: the first page by stars holds invidious, a YouTube front end,
  # and awesome-crystal, a markdown list. So a candidate is confirmed by reading
  # /contents/shard.yml, exactly as the exhaustive sweep confirms its own, and a
  # repository without one is skipped rather than recorded.
  #
  # WHAT IT COSTS, AND OUT OF WHICH BUDGET.
  #
  # One search request per page, and one contents request per candidate on that
  # page. The search request is the interesting one: measured live against an
  # authenticated token, /search/repositories reports
  # `x-ratelimit-resource: search` with a limit of 30 a minute, while
  # /search/code reports `x-ratelimit-resource: code_search` with a limit of 10.
  # They are separate buckets, so this pass does not slow the exhaustive sweep
  # down; a page of it costs one request from a bucket the size-window crawl
  # never touches. The contents requests are core, 5000 an hour, shared with the
  # exhaustive sweep and the indexer, which is why the page bound is small.
  #
  # WHY IT NEVER CLAIMS TO BE COMPLETE.
  #
  # A search returns at most 1000 results however many matched, and unlike the
  # size partition there is no way to split a star ranking into disjoint windows
  # that code search would accept. So this pass sees the top 1000 of each seed
  # and nothing below it, which is the point rather than a defect: everything
  # below is what the exhaustive sweep is for. It records
  # `completed_rank_capped` and never `completed_exhaustive`.
  class HighValueCrawler < BaseCrawler
    include GithubApi

    HOST = "github.com"

    # The crawl_states row this pass resumes from, which is deliberately not
    # github.com's. Two cursors, two purposes: this one walks a star ranking
    # that has an end and then starts again, and the host's one walks a size
    # partition that must advance monotonically until the whole host is seen.
    # Sharing a row would make each pass reset the other, and the exhaustive
    # sweep would never get past the smallest manifests.
    #
    # The slash is what makes the key safe. ShardIdentity::HOST_PATTERN rejects
    # anything containing one, so this string can never be mistaken for a host
    # by the code that reads crawl_states rows.
    STATE_KEY = "github.com/high-value"

    # GitHub returns at most this many results per query however many matched.
    RESULT_CAP = 1000
    PER_PAGE   =  100

    # Pages of 100 candidates one run walks before it stops with its cursor
    # saved.
    #
    # Three, because of what a page costs on the core budget rather than what it
    # costs on the search budget. A page is one search request, which bills the
    # 30 a minute search bucket, plus up to 100 contents requests, which bill
    # core. Three pages is therefore up to 300 core requests and 3 search ones.
    # The scheduled Job already spends about 1000 core on the exhaustive
    # github.com sweep and about 900 indexing 300 shards, so this brings one run
    # to roughly 2200 of the 5000 core requests an hour a token gets, and it runs
    # six-hourly. On the search side it spends 3 of 30 in a minute, and none of
    # the code_search bucket the exhaustive sweep depends on.
    #
    # It is also enough to matter on the first run: kemalcr/kemal is fourth by
    # stars, and every Crystal shard with more than 500 stars is inside the
    # first three pages of the first seed.
    DEFAULT_MAX_PAGES = 3

    # Ranked seeds, walked in order. Sorted by stars descending, which is the
    # entire reason this pass reads repository search instead of code search.
    SEEDS = [
      "language:Crystal",
      "topic:crystal",
    ]

    def initialize(
      base_url : String? = nil,
      token : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
      max_pages : Int32 = DEFAULT_MAX_PAGES,
    )
      # The credential is github.com's; only the cursor is this pass's own.
      super(
        host: STATE_KEY,
        base_url: base_url,
        token: token || Credentials.token_for(HOST),
        sleeper: sleeper,
        max_pages: max_pages,
      )
    end

    # Never. The top 1000 of a ranked query is not the host, and no partition of
    # a star ranking would make it so. Saying otherwise here would let a
    # finished pass be recorded as a complete view of github.com, which is the
    # one thing the exhaustive sweep exists to be.
    def exhaustive? : Bool
      false
    end

    def coverage_reason : String
      CrawlState::StopReason::COMPLETED_RANK_CAPPED
    end

    def fetch_page(cursor : String?) : CrawlPage
      position = Position.load(cursor)
      response = search(position.query, position.page)
      total = response["total_count"]?.try(&.as_i?) || 0

      items = response["items"]?.try(&.as_a?) || [] of JSON::Any
      repositories = items.compact_map { |item| to_repository(item) }

      last_page = (Math.min(total, RESULT_CAP) - 1) // PER_PAGE + 1
      next_position = if position.page >= last_page || items.empty?
                        position.advance_seed
                      else
                        position.advance_page
                      end

      CrawlPage.new(repositories, next_position.try(&.to_cursor))
    end

    private def search(query : String, page : Int32) : JSON::Any
      params = URI::Params.encode({
        "q"        => query,
        "sort"     => "stars",
        "order"    => "desc",
        "per_page" => PER_PAGE.to_s,
        "page"     => page.to_s,
      })
      client.get_json("/search/repositories?#{params}")
    end

    # Repository search hands back the repository itself rather than a file
    # inside it, so the star count, the fork count and the homepage arrive with
    # the candidate. They are carried on the record and written by the
    # registrar, which is why a shard this pass finds has a star count before
    # the indexer has ever looked at it.
    private def to_repository(item : JSON::Any) : DiscoveredRepository?
      full_name = item["full_name"]?.try(&.as_s?)
      return nil unless full_name

      owner, _, repo = full_name.partition('/')
      return nil if owner.empty? || repo.empty?

      DiscoveredRepository.new(
        host: HOST,
        owner: owner,
        repo: repo,
        repository_url: item["html_url"]?.try(&.as_s?) || "https://github.com/#{full_name}",
        description: item["description"]?.try(&.as_s?),
        homepage_url: item["homepage"]?.try(&.as_s?).presence,
        default_branch: item["default_branch"]?.try(&.as_s?),
        stars: item["stargazers_count"]?.try(&.as_i?),
        forks: item["forks_count"]?.try(&.as_i?),
      )
    end

    # Where in the ranking a run stopped: which seed, and which page of it.
    # Serialized as JSON into the crawl_states cursor, so consecutive runs
    # advance through the seeds instead of re-reading the same top hundred every
    # six hours.
    #
    # A cycle ends when the last seed runs out of pages, and the cursor is
    # cleared rather than pinned at the end. That is deliberate: a ranking is
    # never finished the way a partition is, because the ranking moves. Clearing
    # it makes the next run start the cycle again, which is how a shard that
    # gained stars since the last pass gets seen, and it makes CrawlRunner reset
    # the counts, so the row describes one cycle rather than every cycle ever.
    struct Position
      getter seed : Int32
      getter page : Int32

      def initialize(@seed : Int32, @page : Int32)
      end

      def self.initial : Position
        new(seed: 0, page: 1)
      end

      def self.load(cursor : String?) : Position
        return initial unless cursor

        parsed = JSON.parse(cursor)
        return initial unless parsed.as_h?

        seed = parsed["seed"]?.try(&.as_i?)
        page = parsed["page"]?.try(&.as_i?)
        return initial unless seed && page
        return initial unless seed >= 0 && seed < SEEDS.size && page >= 1

        new(seed: seed, page: page)
      rescue JSON::ParseException
        # A cursor we cannot read is worse than no cursor: resuming from a
        # misread position would skip pages of the ranking silently.
        Log.warn { "Discarding unreadable #{STATE_KEY} crawl cursor" }
        initial
      end

      def query : String
        SEEDS[seed]
      end

      def advance_page : Position
        Position.new(seed: seed, page: page + 1)
      end

      # The next seed, or nil when this was the last one. Nil ends the cycle.
      def advance_seed : Position?
        following = seed + 1
        return nil if following >= SEEDS.size

        Position.new(seed: following, page: 1)
      end

      def to_cursor : String
        {seed: seed, page: page}.to_json
      end
    end
  end
end
