require "json"
require "./base_crawler"
require "./github_api"

module Discovery
  # One page of GitHub code search for a term somebody typed into the search box.
  #
  # The scheduled sweep enumerates github.com by partitioning code search on
  # shard.yml file size, which is exhaustive and answers a question nobody asked.
  # This asks the visitor's question instead: of the repositories with a
  # shard.yml at their root, which ones match this word. Same endpoint, same
  # credential, same "is it really a shard" check, different query, and one page
  # rather than a partition.
  #
  # It is a BaseCrawler and not a bespoke fetch loop, and that is most of why it
  # is short. Reading a candidate's shard.yml to confirm it is a shard and to
  # take its real name, registering through ShardIdentity so a second sighting
  # updates rather than duplicates, counting outcomes, and turning a rate limit
  # into a partial result with nothing half-written are all behaviours the
  # engine already has and that a probe needs exactly as much as a sweep does.
  # The only thing this supplies is the query.
  #
  # WHY ONE PAGE.
  #
  # The caller is a page load. A second page is a second code_search request
  # from a bucket that allows ten a minute, spent to lengthen a result list
  # whose first page the visitor has not looked at yet. The bound belongs where
  # the cost is felt, so `fetch_page` reports the enumeration finished after one
  # page and `exhaustive?` says plainly that this is not a complete view of the
  # host: PER_PAGE matches is what a probe promises, not "every shard matching
  # this word".
  class KeywordCrawler < BaseCrawler
    include GithubApi

    HOST = "github.com"

    # Candidates per probe.
    #
    # Each one costs a core request to read its shard.yml, on top of the one
    # code_search request the query itself costs, and all of it happens while
    # somebody waits for a page. Ten is a search result page's worth of new
    # shards, which is far more than a query returning nothing today needs to
    # stop being useless, and eleven requests is a latency a reader tolerates.
    PER_PAGE = 10

    getter term : String

    def initialize(
      @term : String,
      base_url : String? = nil,
      token : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
    )
      # max_pages 1 as well as the single-page cursor below. The cursor is what
      # makes the enumeration finish; this is what stops a future change to it
      # turning a page load into a full walk of a host.
      super(host: HOST, base_url: base_url, token: token, sleeper: sleeper, max_pages: 1)
    end

    # Never. A probe reads the first page of one query, and calling that a
    # complete view of github.com for this term would be a lie in the one place
    # the registry records how much it has actually seen.
    def exhaustive? : Bool
      false
    end

    def coverage_reason : String
      CrawlState::StopReason::COMPLETED_TOPIC_SCOPED
    end

    def fetch_page(cursor : String?) : CrawlPage
      # The cursor is the finished flag. One page, then done.
      return CrawlPage.new([] of DiscoveredRepository, nil) if cursor

      response = search
      items = response["items"]?.try(&.as_a?) || [] of JSON::Any

      CrawlPage.new(items.compact_map { |item| to_repository(item) }, nil)
    end

    # `filename:shard.yml path:/` is the same qualifier pair the exhaustive
    # sweep uses, and it carries the same meaning: a repository matches because
    # it has a shard.yml at its root. The term is added to it rather than
    # replacing it, so a probe can only ever surface shards. Searching the term
    # alone would return applications, dotfiles and every README that mentions
    # the word.
    #
    # The term is not quoted. GitHub's code search treats a bare word as a
    # token match against the file's content and its path, which is what finds
    # `name: kemal` inside a manifest as well as a repository called kemal.
    # Quoting it would demand a literal phrase and miss both.
    private def search : JSON::Any
      query = "#{sanitized_term} filename:shard.yml path:/"
      params = URI::Params.encode({
        "q"        => query,
        "per_page" => PER_PAGE.to_s,
      })
      client.get_json("/search/code?#{params}")
    end

    # Qualifier syntax stripped out of the visitor's term.
    #
    # A search box is user input and this interpolates it into a query language.
    # The damage a colon can do here is not injection in the SQL sense, because
    # there is nothing to escape into: it is that `org:evil` or `path:/etc`
    # silently changes which repositories a probe registers, using our
    # credential, on behalf of whoever typed it. Reduced to the characters a
    # package name can contain, so what reaches GitHub is a word and never a
    # directive.
    private def sanitized_term : String
      term.gsub(/[^A-Za-z0-9._\- ]/, " ").squeeze(' ').strip
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
  end
end
