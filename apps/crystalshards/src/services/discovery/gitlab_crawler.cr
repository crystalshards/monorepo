require "json"
require "./base_crawler"

module Discovery
  # Finds shards on GitLab by enumerating projects tagged with the "crystal"
  # topic, then checking each one for a shard.yml at its root.
  #
  # This host does not offer what GitHub's code search offers. GitLab's public
  # projects API has no language filter, and its blob search, which could ask for
  # shard.yml directly, answers an unauthenticated request with 401 and depends on
  # the instance's advanced search being available to the token. Enumerating every
  # project on gitlab.com to look for shard.yml is not a crawl anyone should run.
  #
  # So the sweep uses the topic, and is honest that this is not everything: a
  # shard whose author never tagged the project is not discovered here, and a
  # finished sweep is recorded as partial for that reason. Those shards still
  # reach the registry the way they always have, by being submitted.
  class GitlabCrawler < BaseCrawler
    HOST     = "gitlab.com"
    TOPIC    = "crystal"
    PER_PAGE = 100

    def initialize(
      base_url : String? = nil,
      token : String? = nil,
      sleeper : Proc(Time::Span, Nil)? = nil,
      max_pages : Int32? = nil,
    )
      super(host: HOST, base_url: base_url, token: token, sleeper: sleeper, max_pages: max_pages)
    end

    def default_base_url : String
      "https://gitlab.com/api/v4"
    end

    def auth_headers(token : String?) : HTTP::Headers
      headers = HTTP::Headers{"Accept" => "application/json"}
      headers["PRIVATE-TOKEN"] = token if token
      headers
    end

    # Topic-scoped, so a finished sweep has seen every project that carries the
    # topic and nothing about the ones that do not.
    def exhaustive? : Bool
      false
    end

    def fetch_page(cursor : String?) : CrawlPage
      page = (cursor.try(&.to_i?) || 1)

      params = URI::Params.encode({
        "topic"    => TOPIC,
        "order_by" => "id",
        "sort"     => "asc",
        "per_page" => PER_PAGE.to_s,
        "page"     => page.to_s,
        "archived" => "false",
      })
      payload = client.get_json("/projects?#{params}")
      projects = payload.as_a? || [] of JSON::Any

      repositories = projects.compact_map { |project| to_repository(project) }

      # GitLab states the next page in a header, and an empty value means this was
      # the last one. Trusting the header rather than counting pages ourselves is
      # what keeps a sweep from stopping one page early.
      next_page = client.last_headers["x-next-page"]?.try(&.strip).presence

      CrawlPage.new(repositories, next_page)
    end

    def fetch_shard_yml(repository : DiscoveredRepository) : String?
      project_path = URI.encode_path_segment("#{repository.owner}/#{repository.repo}")
      ref = repository.default_branch || "HEAD"
      path = "/projects/#{project_path}/repository/files/shard.yml/raw?ref=#{URI.encode_path_segment(ref)}"

      client.get(path)
    rescue HostClient::NotFound
      nil
    end

    private def to_repository(project : JSON::Any) : DiscoveredRepository?
      full_path = project["path_with_namespace"]?.try(&.as_s?)
      return nil unless full_path

      segments = full_path.split('/')

      # A project inside a subgroup is more than two segments. It is counted as
      # skipped and logged with its path, rather than dropped quietly: the
      # alternative is a row whose URL does not lead back to the project.
      #
      # The wording comes from ShardIdentity so the crawl log, the identity_error
      # on a row and the operator's report all explain it the same way.
      unless segments.size == 2
        report.skipped += 1
        Log.info { "#{HOST}: skipping #{full_path}: #{ShardIdentity::NESTED_NAMESPACE}" }
        return nil
      end

      DiscoveredRepository.new(
        host: HOST,
        owner: segments[0],
        repo: segments[1],
        repository_url: project["web_url"]?.try(&.as_s?) || "https://gitlab.com/#{full_path}",
        description: project["description"]?.try(&.as_s?),
        default_branch: project["default_branch"]?.try(&.as_s?),
        stars: project["star_count"]?.try(&.as_i?),
        forks: project["forks_count"]?.try(&.as_i?),
      )
    end
  end
end
