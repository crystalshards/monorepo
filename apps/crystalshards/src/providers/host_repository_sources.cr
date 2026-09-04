require "http/client"
require "json"
require "uri"
require "base64"
require "./repository_source"
require "../services/discovery/credentials"

# The non-GitHub hosts discovery crawls, each reading its own API.
#
# All three publish a tag list and a raw file endpoint, so a GitLab, Codeberg or
# Bitbucket shard gets the same page as a GitHub one: repository facts, every
# tag as a version row, the latest version's manifest parsed, dependency edges
# and a README. None of them is a degraded path.
#
# Two of them are better than GitHub here, which is worth noting because it
# shaped the GitHub design: GitLab and Bitbucket both return a DATE with each
# tag, so their version rows are dated from one request. GitHub's /tags does
# not, which is why the GitHub source spends one extra request dating the single
# version it indexes.
#
# Rate limits, measured from published documentation rather than guessed:
#   gitlab.com     2000 authenticated requests per minute per user
#   codeberg.org   Gitea default, no published per-token API quota
#   bitbucket.org  1000 requests per hour per token
# All three are far looser per shard than GitHub's core pool, and the same
# per-run bound covers them.
abstract class HostRepositorySource < RepositorySource
  record Response, status : Int32, body : String

  alias Requester = Proc(String, HTTP::Headers, Response)

  DEFAULT_REQUESTER = ->(url : String, headers : HTTP::Headers) do
    response = HTTP::Client.get(url, headers: headers)
    Response.new(response.status_code, response.body)
  end

  getter repo_path : String
  getter requests_made : Int32 = 0

  def initialize(
    @repo_path : String,
    @token : String? = nil,
    @requester : Requester = DEFAULT_REQUESTER,
  )
  end

  # Per-host wiring. Each subclass answers these and inherits everything else.
  abstract def host_name : String
  abstract def repository_url : String
  abstract def tags_url : String
  abstract def raw_url(ref : String, path : String) : String
  abstract def parse_repository(document : JSON::Any) : RepositorySnapshot
  abstract def parse_tag(node : JSON::Any, fallback : Time?) : RepositorySnapshot::Ref?

  # The header this host authenticates with. Nil token means unauthenticated,
  # which every one of these allows at a lower quota.
  def auth_headers : HTTP::Headers
    HTTP::Headers.new
  end

  def fetch_snapshot : RepositorySnapshot
    snapshot = parse_repository(get_json(repository_url))
    refs = fetch_tags(snapshot.pushed_at)

    if refs.empty?
      if branch = RepositorySnapshot.branch_ref(snapshot.default_branch, snapshot.pushed_at)
        refs << branch
      end
    end

    RepositorySnapshot.new(
      stars: snapshot.stars,
      forks: snapshot.forks,
      description: snapshot.description,
      homepage: snapshot.homepage,
      license: snapshot.license,
      topics: snapshot.topics,
      default_branch: snapshot.default_branch,
      pushed_at: snapshot.pushed_at,
      archived: snapshot.archived,
      refs: refs,
    )
  end

  def fetch_file(ref : String, path : String) : RepositorySource::FileOutcome
    response = perform(raw_url(ref, path), authenticated: false)

    case response.status
    when 200 then RepositorySource::FileResult::Found.new(response.body)
    when 404 then RepositorySource::FileResult::Absent.new
    else          RepositorySource::FileResult::Failed.new("HTTP #{response.status}")
    end
  rescue ex : RepositorySource::Error
    RepositorySource::FileResult::Failed.new(ex.message || ex.class.name)
  end

  private def fetch_tags(fallback : Time?) : Array(RepositorySnapshot::Ref)
    document = get_json(tags_url)
    nodes = tag_nodes(document)
    return [] of RepositorySnapshot::Ref unless nodes

    nodes.compact_map { |node| parse_tag(node, fallback) }
  end

  # Most of these answer a bare array; Bitbucket wraps its pages in `values`.
  def tag_nodes(document : JSON::Any) : Array(JSON::Any)?
    document.as_a? || document["values"]?.try(&.as_a?)
  end

  protected def get_json(url : String) : JSON::Any
    response = perform(url)

    case response.status
    when 200 then JSON.parse(response.body)
    when 404 then raise RepositorySource::NotFound.new("#{repo_path} is not a repository this credential can see")
    when 301, 302, 307, 308
      # A renamed or transferred repository on GitLab, Codeberg or Bitbucket
      # answers 3xx. That slug no longer addresses a repository, so it belongs
      # in NotFound rather than Error. Error is retried on every pass forever
      # and renders as a fault, while NotFound marks the row unavailable, which
      # is what a slug that has stopped naming a repository is. Measured:
      # codeberg.org/w0u7/email_octopus, in the registry since 2026-08-19 with
      # no versions, answers 301.
      #
      # The new name is deliberately not chased, for the reason GithubRepositoryApi
      # gives: adopting it would merge two identities the registry keys rows on,
      # and these APIs do not name the new owner and repo without another round
      # trip. A moved repository is reported as moved; re-pointing it is a
      # registration decision rather than a fetch.
      raise RepositorySource::NotFound.new(
        "#{repo_path} has moved: that owner and name no longer address a repository on #{host_name}"
      )
    when 401, 403 then raise RepositorySource::Error.new("#{repo_path} was refused: HTTP #{response.status}")
    else               raise RepositorySource::Error.new("#{repo_path} answered HTTP #{response.status}")
    end
  rescue ex : JSON::ParseException
    raise RepositorySource::Error.new("#{repo_path} did not answer with JSON: #{ex.message}")
  end

  protected def perform(url : String, authenticated : Bool = true) : Response
    headers = HTTP::Headers{"User-Agent" => "crystalshards.org shard indexing"}
    if authenticated
      auth_headers.each { |name, values| values.each { |value| headers.add(name, value) } }
    end

    @requests_made += 1
    @requester.call(url, headers)
  rescue ex : IO::Error | Socket::Error
    raise RepositorySource::Error.new("GET #{url} failed: #{ex.message}")
  end

  protected def parse_time(value : String?) : Time?
    return nil unless value

    Time.parse_rfc3339(value)
  rescue Time::Format::Error
    nil
  end

  protected def presence_of(value : JSON::Any?) : String?
    value.try(&.as_s?).presence
  end

  # Everything except refs; fetch_snapshot merges the tag list in.
  protected def facts(
    stars : Int32? = nil,
    forks : Int32? = nil,
    description : String? = nil,
    homepage : String? = nil,
    license : String? = nil,
    topics : Array(String) = [] of String,
    default_branch : String? = nil,
    pushed_at : Time? = nil,
    archived : Bool? = nil,
  ) : RepositorySnapshot
    RepositorySnapshot.new(
      stars: stars, forks: forks, description: description, homepage: homepage,
      license: license, topics: topics, default_branch: default_branch,
      pushed_at: pushed_at, archived: archived,
    )
  end
end

# GET /api/v4/projects/{url-encoded path}
# GET /api/v4/projects/{id}/repository/tags       dated, newest first
class GitlabRepositorySource < HostRepositorySource
  API_BASE = "https://gitlab.com/api/v4"

  def host_name : String
    "GitLab"
  end

  # GitLab addresses a project by its whole namespaced path, URL-encoded.
  private def project_id : String
    URI.encode_path_segment(repo_path)
  end

  def repository_url : String
    "#{API_BASE}/projects/#{project_id}"
  end

  def tags_url : String
    "#{API_BASE}/projects/#{project_id}/repository/tags?per_page=100"
  end

  def raw_url(ref : String, path : String) : String
    "https://gitlab.com/#{repo_path}/-/raw/#{ref}/#{path}"
  end

  def auth_headers : HTTP::Headers
    token = @token
    token ? HTTP::Headers{"PRIVATE-TOKEN" => token} : HTTP::Headers.new
  end

  def parse_repository(document : JSON::Any) : RepositorySnapshot
    facts(
      stars: document["star_count"]?.try(&.as_i?),
      forks: document["forks_count"]?.try(&.as_i?),
      description: presence_of(document["description"]?),
      homepage: presence_of(document["web_url"]?),
      # as_h? first: a JSON null is truthy as a JSON::Any, so indexing it raises.
      license: presence_of(document["license"]?.try(&.as_h?).try(&.["key"]?)),
      topics: document["topics"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String,
      default_branch: document["default_branch"]?.try(&.as_s?),
      pushed_at: parse_time(document["last_activity_at"]?.try(&.as_s?)),
      archived: document["archived"]?.try(&.as_bool?),
    )
  end

  def parse_tag(node : JSON::Any, fallback : Time?) : RepositorySnapshot::Ref?
    name = node["name"]?.try(&.as_s?)
    return nil unless name && !name.empty?

    commit = node["commit"]?

    RepositorySnapshot::Ref.from_tag(
      name,
      commit_sha: commit.try(&.["id"]?).try(&.as_s?),
      committed_at: parse_time(commit.try(&.["committed_date"]?).try(&.as_s?)) || fallback,
    )
  end
end

# Gitea's API. GET /api/v1/repos/{owner}/{repo}[/tags]
class CodebergRepositorySource < HostRepositorySource
  API_BASE = "https://codeberg.org/api/v1"

  def host_name : String
    "Codeberg"
  end

  def repository_url : String
    "#{API_BASE}/repos/#{repo_path}"
  end

  def tags_url : String
    "#{API_BASE}/repos/#{repo_path}/tags?limit=100"
  end

  def raw_url(ref : String, path : String) : String
    "https://codeberg.org/#{repo_path}/raw/#{ref}/#{path}"
  end

  def auth_headers : HTTP::Headers
    token = @token
    token ? HTTP::Headers{"Authorization" => "token #{token}"} : HTTP::Headers.new
  end

  def parse_repository(document : JSON::Any) : RepositorySnapshot
    facts(
      stars: document["stars_count"]?.try(&.as_i?),
      forks: document["forks_count"]?.try(&.as_i?),
      description: presence_of(document["description"]?),
      homepage: presence_of(document["website"]?),
      topics: document["topics"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String,
      default_branch: document["default_branch"]?.try(&.as_s?),
      pushed_at: parse_time(document["updated_at"]?.try(&.as_s?)),
      archived: document["archived"]?.try(&.as_bool?),
    )
  end

  # Gitea nests the commit date under commit.created, and only on some
  # versions, so the repository's updated_at is the fallback.
  def parse_tag(node : JSON::Any, fallback : Time?) : RepositorySnapshot::Ref?
    name = node["name"]?.try(&.as_s?)
    return nil unless name && !name.empty?

    commit = node["commit"]?

    RepositorySnapshot::Ref.from_tag(
      name,
      commit_sha: commit.try(&.["sha"]?).try(&.as_s?),
      committed_at: parse_time(commit.try(&.["created"]?).try(&.as_s?)) || fallback,
    )
  end
end

# GET /2.0/repositories/{workspace}/{repo}[/refs/tags]
class BitbucketRepositorySource < HostRepositorySource
  API_BASE = "https://api.bitbucket.org/2.0"

  def host_name : String
    "Bitbucket"
  end

  def repository_url : String
    "#{API_BASE}/repositories/#{repo_path}"
  end

  def tags_url : String
    "#{API_BASE}/repositories/#{repo_path}/refs/tags?pagelen=100&sort=-target.date"
  end

  def raw_url(ref : String, path : String) : String
    "https://bitbucket.org/#{repo_path}/raw/#{ref}/#{path}"
  end

  def auth_headers : HTTP::Headers
    # Bitbucket app passwords authenticate as basic auth with the account name,
    # which is the pair Credentials already requires for the crawler.
    token = @token
    return HTTP::Headers.new unless token

    if account = Discovery::Credentials.username_for?("bitbucket.org")
      encoded = Base64.strict_encode("#{account}:#{token}")
      HTTP::Headers{"Authorization" => "Basic #{encoded}"}
    else
      HTTP::Headers{"Authorization" => "Bearer #{token}"}
    end
  end

  def parse_repository(document : JSON::Any) : RepositorySnapshot
    facts(
      description: presence_of(document["description"]?),
      homepage: presence_of(document["website"]?),
      # Bitbucket has no stars. Left nil rather than zeroed, because zero would
      # read as "nobody starred this" on a host with no such button.
      default_branch: document["mainbranch"]?.try(&.as_h?).try(&.["name"]?).try(&.as_s?),
      pushed_at: parse_time(document["updated_on"]?.try(&.as_s?)),
    )
  end

  def parse_tag(node : JSON::Any, fallback : Time?) : RepositorySnapshot::Ref?
    name = node["name"]?.try(&.as_s?)
    return nil unless name && !name.empty?

    target = node["target"]?

    RepositorySnapshot::Ref.from_tag(
      name,
      commit_sha: target.try(&.["hash"]?).try(&.as_s?),
      committed_at: parse_time(target.try(&.["date"]?).try(&.as_s?)) || fallback,
    )
  end
end
