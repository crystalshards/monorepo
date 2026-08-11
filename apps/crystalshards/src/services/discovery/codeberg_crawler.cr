require "json"
require "./base_crawler"

module Discovery
  # Finds shards on Codeberg, which runs Forgejo and serves the Gitea API at
  # /api/v1.
  #
  # The enumeration is the repository search restricted to topics. The parameter
  # shape is worth spelling out because getting it wrong is silent and expensive:
  # in this API `topic` is a boolean meaning "match the query against topics", and
  # `q` carries the term. Sending `topic=crystal` parses as a false boolean, the
  # filter drops off, and the search happily returns every repository on the
  # instance, which is around 412,000. That crawl would appear to work.
  #
  # Like GitLab, this is topic-scoped rather than exhaustive, so a finished sweep
  # is recorded as partial: a shard on Codeberg whose author did not add the
  # topic is not found this way.
  class CodebergCrawler < BaseCrawler
    HOST  = "codeberg.org"
    TOPIC = "crystal"
    LIMIT = 50

    def initialize(
      base_url : String? = nil,
      token : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
      max_pages : Int32? = nil,
    )
      super(host: HOST, base_url: base_url, token: token, sleeper: sleeper, max_pages: max_pages)
    end

    def default_base_url : String
      "https://codeberg.org/api/v1"
    end

    def auth_headers(token : String?) : HTTP::Headers
      headers = HTTP::Headers{"Accept" => "application/json"}
      headers["Authorization"] = "token #{token}" if token
      headers
    end

    def exhaustive? : Bool
      false
    end

    def fetch_page(cursor : String?) : CrawlPage
      page = (cursor.try(&.to_i?) || 1)

      params = URI::Params.encode({
        "q"        => TOPIC,
        "topic"    => "true",
        "limit"    => LIMIT.to_s,
        "page"     => page.to_s,
        "archived" => "false",
      })

      payload = client.get_json("/repos/search?#{params}")
      repositories = (payload["data"]?.try(&.as_a?) || [] of JSON::Any).compact_map { |repo| to_repository(repo) }

      # This API reports the total across all pages in a header and does not say
      # "no more pages" any other way, so the end of the enumeration is a page
      # that came back short. Counting against x-total-count as well means a
      # truncated response cannot be mistaken for the end.
      returned = payload["data"]?.try(&.as_a?).try(&.size) || 0
      total = client.last_headers["x-total-count"]?.try(&.strip).try(&.to_i?)
      seen = (page - 1) * LIMIT + returned

      next_cursor = if returned == 0
                      nil
                    elsif total && seen >= total
                      nil
                    else
                      (page + 1).to_s
                    end

      CrawlPage.new(repositories, next_cursor)
    end

    def fetch_shard_yml(repository : DiscoveredRepository) : String?
      ref = repository.default_branch
      path = if ref
               "/repos/#{repository.owner}/#{repository.repo}/raw/shard.yml?ref=#{URI.encode_path_segment(ref)}"
             else
               "/repos/#{repository.owner}/#{repository.repo}/raw/shard.yml"
             end

      client.get(path)
    rescue HostClient::NotFound
      nil
    end

    private def to_repository(repo : JSON::Any) : DiscoveredRepository?
      full_name = repo["full_name"]?.try(&.as_s?)
      return nil unless full_name

      owner, _, name = full_name.partition('/')
      return nil if owner.empty? || name.empty?

      DiscoveredRepository.new(
        host: HOST,
        owner: owner,
        repo: name,
        repository_url: repo["html_url"]?.try(&.as_s?) || "https://codeberg.org/#{full_name}",
        description: repo["description"]?.try(&.as_s?),
        homepage_url: repo["website"]?.try(&.as_s?).presence,
        default_branch: repo["default_branch"]?.try(&.as_s?),
        stars: repo["stars_count"]?.try(&.as_i?),
        forks: repo["forks_count"]?.try(&.as_i?),
      )
    end
  end
end
