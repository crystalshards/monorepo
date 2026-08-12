require "http/client"
require "json"
require "./repository_source"

# The GitHub calls indexing makes, and why these ones.
#
# WHICH ENDPOINT RETURNS THE TAG LIST. Measured against the live API on
# kemalcr/kemal rather than assumed:
#
#   GET /repos/{owner}/{repo}/tags?per_page=100
#       1 request, x-ratelimit-resource: core. Returned all 65 of kemal's tags
#       newest-first with name and commit sha. This is the cheapest call that
#       returns the tag list and it is the one used.
#
#       It returns no DATE for any tag. Dating all 65 would cost one
#       GET /commits/{sha} each, so 65 core requests for one shard, which
#       against 5696 repositories is not a budget question but an impossibility.
#       So exactly one commit is dated per shard: the tag actually being
#       indexed. Older tags are recorded with their ref and sha and are dated
#       from the repository's pushed_at until something asks for them, which is
#       the same "fetch older versions on demand" shape the page uses.
#
#   GET /repos/{owner}/{repo}
#       1 request, core. Stars, forks, description, homepage, license, topics,
#       default branch, pushed_at, archived.
#
#   GET /repos/{owner}/{repo}/commits/{sha}
#       1 request, core. The committed date for the one tag being indexed.
#
#   https://raw.githubusercontent.com/{repo}/{ref}/{path}
#       Not the contents API. The contents API costs a core request per file and
#       base64-encodes the body; raw serves bytes off a CDN and its responses
#       carry no x-ratelimit headers, so shard.yml and README do not draw on the
#       5000/hour core pool the crawl depends on.
#
# Three core requests per shard, then. A POST /graphql could collapse those
# three into one on a separate 5000/hour pool and would return every tag date,
# which was measured and is real. It is deliberately not used: it is a second
# authentication and query surface whose failure path would run only in
# production, where no fixture exercises it. One transport that the specs drive
# end to end is worth more here than one saved request per shard, and the bound
# on a run is what actually keeps the budget, not the per-shard cost.
class GithubRepositoryApi < RepositorySource
  API_BASE = "https://api.github.com"
  RAW_BASE = "https://raw.githubusercontent.com"

  # GitHub serves at most 100 tags per page. The newest 100 are the ones a page
  # can show; paginating further would multiply every shard's cost for versions
  # nobody selects.
  MAX_TAGS = 100

  record Response, status : Int32, body : String

  # Every HTTP call goes through here, so specs drive this class entirely from
  # fixtures with no network.
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

  # DISCOVERY_GITHUB_TOKEN is the one the Cloud Run Job already holds;
  # GITHUB_TOKEN is what a developer running this locally is likely to have.
  # Unauthenticated works and is rate limited to 60 requests an hour, which is
  # enough for one shard and useless for a sweep.
  def self.token_from_env : String?
    ENV["DISCOVERY_GITHUB_TOKEN"]?.presence || ENV["GITHUB_TOKEN"]?.presence
  end

  # Repository facts plus the tag list, as one value. Two core requests.
  def fetch_snapshot : RepositorySnapshot
    repository = fetch_repository_json

    default_branch = repository["default_branch"]?.try(&.as_s?)
    pushed_at = parse_time(repository["pushed_at"]?.try(&.as_s?))

    refs = fetch_tags(pushed_at)

    # No tags is a normal state for a large part of this corpus, not a failure.
    # The default branch stands in so the shard still gets a page, a manifest
    # and dependency edges rather than reading as a shard with no versions.
    if refs.empty?
      if branch = RepositorySnapshot.branch_ref(default_branch, pushed_at)
        refs << branch
      end
    end

    RepositorySnapshot.new(
      stars: repository["stargazers_count"]?.try(&.as_i?),
      forks: repository["forks_count"]?.try(&.as_i?),
      description: presence_of(repository["description"]?),
      homepage: presence_of(repository["homepage"]?),
      # `as_h?` first, because a repository with no licence answers
      # "license": null, and a JSON::Any wrapping null is truthy. `try` does not
      # guard it, so indexing the field raised and cost the shard its whole
      # pass. Measured: 8 of 60 shards in one local run.
      license: presence_of(repository["license"]?.try(&.as_h?).try(&.["spdx_id"]?)),
      topics: repository["topics"]?.try(&.as_a?).try(&.compact_map(&.as_s?)) || [] of String,
      default_branch: default_branch,
      pushed_at: pushed_at,
      archived: repository["archived"]?.try(&.as_bool?),
      refs: refs,
    )
  end

  # The commit date for one ref. Called once per shard, for the version actually
  # being indexed, because the tag list carries no dates.
  def fetch_commit_date(sha : String) : Time?
    response = perform("#{API_BASE}/repos/#{repo_path}/commits/#{sha}")
    return nil unless response.status == 200

    committer = JSON.parse(response.body).dig?("commit", "committer", "date")
    parse_time(committer.try(&.as_s?))
  rescue ex : RepositorySource::Error | JSON::ParseException
    Log.debug { "Could not date #{repo_path}@#{sha}: #{ex.message}" }
    nil
  end

  private def fetch_repository_json : JSON::Any
    response = perform("#{API_BASE}/repos/#{repo_path}")

    case response.status
    when 200 then JSON.parse(response.body)
    when 404 then raise RepositorySource::NotFound.new("#{repo_path} is not a repository this token can see")
    when 403 then raise RepositorySource::Error.new("#{repo_path} metadata was refused: HTTP 403, rate limit or permissions")
    else          raise RepositorySource::Error.new("#{repo_path} metadata answered HTTP #{response.status}")
    end
  rescue ex : JSON::ParseException
    raise RepositorySource::Error.new("#{repo_path} metadata was not JSON: #{ex.message}")
  end

  # The tag list. Newest first, undated: `released_at` falls back to the
  # repository's pushed_at until a tag is the one being indexed, at which point
  # the caller dates it properly with fetch_commit_date.
  private def fetch_tags(pushed_at : Time?) : Array(RepositorySnapshot::Ref)
    response = perform("#{API_BASE}/repos/#{repo_path}/tags?per_page=#{MAX_TAGS}")

    case response.status
    when 200
      parsed = JSON.parse(response.body).as_a?
      raise RepositorySource::Error.new("#{repo_path} tags were not a list") unless parsed

      parsed.compact_map do |tag|
        name = tag["name"]?.try(&.as_s?)
        next unless name && !name.empty?

        RepositorySnapshot::Ref.from_tag(
          name,
          commit_sha: tag.dig?("commit", "sha").try(&.as_s?),
          committed_at: pushed_at,
        )
      end
    when 404
      # A repository with no tags answers 200 with an empty array, so a 404 here
      # is the repository disappearing between calls, not an absence of tags.
      raise RepositorySource::NotFound.new("#{repo_path} vanished while its tags were being read")
    when 403
      raise RepositorySource::Error.new("#{repo_path} tags were refused: HTTP 403, rate limit or permissions")
    else
      raise RepositorySource::Error.new("#{repo_path} tags answered HTTP #{response.status}")
    end
  rescue ex : JSON::ParseException
    raise RepositorySource::Error.new("#{repo_path} tags were not JSON: #{ex.message}")
  end

  def fetch_file(ref : String, path : String) : RepositorySource::FileOutcome
    response = perform("#{RAW_BASE}/#{repo_path}/#{ref}/#{path}", authenticated: false)

    case response.status
    when 200 then RepositorySource::FileResult::Found.new(response.body)
    when 404 then RepositorySource::FileResult::Absent.new
    else          RepositorySource::FileResult::Failed.new("HTTP #{response.status}")
    end
  rescue ex : RepositorySource::Error
    RepositorySource::FileResult::Failed.new(ex.message || ex.class.name)
  end

  private def perform(url : String, authenticated : Bool = true) : Response
    headers = HTTP::Headers{
      "Accept"     => "application/vnd.github+json",
      "User-Agent" => "crystalshards.org shard indexing",
    }
    if authenticated && (token = @token)
      headers["Authorization"] = "Bearer #{token}"
    end

    @requests_made += 1
    @requester.call(url, headers)
  rescue ex : IO::Error | Socket::Error
    raise RepositorySource::Error.new("GET #{url} failed: #{ex.message}")
  end

  private def parse_time(value : String?) : Time?
    return nil unless value

    Time.parse_rfc3339(value)
  rescue Time::Format::Error
    nil
  end

  private def presence_of(value : JSON::Any?) : String?
    value.try(&.as_s?).presence
  end
end
