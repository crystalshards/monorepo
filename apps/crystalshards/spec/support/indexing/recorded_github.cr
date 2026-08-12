# src/app.cr requires only services/version_order, so nothing has loaded the
# indexer or the source factory by the time spec_helper globs this directory.
# Required here rather than left to whichever spec happens to load first, so
# this file compiles on its own terms.
require "../../../src/services/shard_indexer"
require "../../../src/providers/repository_source_factory"

# A GitHub API driven from recorded fixtures instead of the network.
#
# Deliberately not a stand-in source. RepositorySourceFactory.builder hands
# back any RepositorySource, so a hand-written double would typecheck, and it
# would also skip the part most likely to be wrong: which URL is called, what
# each status code means, and the split between the rate-limited API and the
# raw file endpoint. This scripts the one Requester proc every call already
# passes through, so the real GithubRepositoryApi runs end to end with nothing
# listening on a port and no route to the internet.
#
# Anything not scripted answers 404, because that is the honest default: a file
# nobody put there is absent, and a spec that meant otherwise has to say so.
class RecordedGithub
  # A tag as /tags returns it: a name and the sha it points at, and no date,
  # which is the whole reason ShardIndexer dates exactly one commit per shard.
  record Tag, name : String, sha : String? = nil

  getter repo_path : String

  # Every URL the api asked for, in order. The assertion behind "one commit
  # request per shard, not one per tag".
  getter requested = [] of String

  # Every host the factory was asked to build this recording for, in order.
  # A gitlab.com shard reaching a source at all is the fact worth asserting
  # now that the indexer is no longer GitHub-only.
  getter asked = [] of String

  @repository_status = 200
  @repository_fields = {} of String => JSON::Any
  @tags_status = 200
  @tags = [] of Tag
  @files = {} of String => {Int32, String}
  @commit_dates = {} of String => Time
  @raise_with : String? = nil

  def initialize(@repo_path : String = "crystal-lang/recorded")
  end

  # The repository endpoint's answer. Only the fields named are present in the
  # body, so "the host did not say" and "the host said zero" stay different
  # things all the way down to the stored row.
  def repository(
    stars : Int32? = nil,
    forks : Int32? = nil,
    description : String? = nil,
    homepage : String? = nil,
    license : String? = nil,
    topics : Array(String)? = nil,
    default_branch : String? = nil,
    pushed_at : Time? = nil,
    archived : Bool? = nil,
  ) : RecordedGithub
    put("stargazers_count", stars)
    put("forks_count", forks)
    put("description", description)
    put("homepage", homepage)
    put("topics", topics.try(&.map { |topic| JSON::Any.new(topic) }))
    put("default_branch", default_branch)
    put("pushed_at", pushed_at.try(&.to_rfc3339))
    put("archived", archived)
    # GitHub nests the licence under a detected-licence object; the shard's own
    # claim in shard.yml is a different field and outranks this one.
    if license
      @repository_fields["license"] = JSON::Any.new({"spdx_id" => JSON::Any.new(license)})
    end

    self
  end

  def repository_status(status : Int32) : RecordedGithub
    @repository_status = status
    self
  end

  # Tag names in the order the host returns them, which is not the order they
  # sort in: shas are derived so a spec can date one without inventing hex.
  def tags(*names : String) : RecordedGithub
    tags(names.map { |name| Tag.new(name, "sha-#{name}") }.to_a)
  end

  def tags(tags : Array(Tag)) : RecordedGithub
    @tags = tags
    self
  end

  def tags_status(status : Int32) : RecordedGithub
    @tags_status = status
    self
  end

  # A file that is there.
  def file(ref : String, path : String, content : String) : RecordedGithub
    @files[key(ref, path)] = {200, content}
    self
  end

  # A file that is not there. The default already, stated when a spec is about
  # the absence.
  def missing(ref : String, path : String) : RecordedGithub
    @files[key(ref, path)] = {404, ""}
    self
  end

  # A file the host would not serve, which is retryable and therefore recorded
  # differently from one that does not exist.
  def file_status(ref : String, path : String, status : Int32) : RecordedGithub
    @files[key(ref, path)] = {status, ""}
    self
  end

  # The committed date for the sha `tags` derived for this tag.
  def dated(tag : String, at : Time) : RecordedGithub
    @commit_dates["sha-#{tag}"] = at
    self
  end

  def commit_date(sha : String, at : Time) : RecordedGithub
    @commit_dates[sha] = at
    self
  end

  # Every request blows up with something GithubRepositoryApi does not convert.
  # IO::Error and Socket::Error become a recorded RepositorySource::Error, so
  # reaching ShardIndexer's caller with an exception takes a different class.
  def raising(message : String) : RecordedGithub
    @raise_with = message
    self
  end

  # A real GithubRepositoryApi, fresh each call because ShardIndexer builds one
  # per pass, sharing this recording so `requested` spans every pass.
  def api : GithubRepositoryApi
    GithubRepositoryApi.new(@repo_path, token: nil, requester: to_requester)
  end

  def to_requester : GithubRepositoryApi::Requester
    ->(url : String, _headers : HTTP::Headers) do
      @requested << url

      if message = @raise_with
        raise Exception.new(message)
      end

      answer(url)
    end
  end

  # Installs this recording behind RepositorySourceFactory.builder for the
  # block, for any host and repo_path. The previous builder is restored in an
  # ensure, so a spec cannot leak a seam into the next one and hand it a
  # network.
  def self.install(github : RecordedGithub, &)
    install({github.repo_path => github}) { yield }
  end

  # Routes by repo_path, for a pass that indexes more than one repository.
  # An unscripted path raises rather than falling through to the real source,
  # because falling through is how a spec quietly acquires a network call.
  def self.install(githubs : Hash(String, RecordedGithub), &)
    previous = RepositorySourceFactory.builder

    # Annotated: the seam is Proc(String, String, RepositorySource?), and an
    # inferred non-nilable return does not satisfy it. Returning nil is the
    # factory's "build the real thing" path, which no spec may take.
    RepositorySourceFactory.builder = ->(host : String, repo_path : String) : RepositorySource? do
      recorded = githubs[repo_path]?
      unless recorded
        raise "No RecordedGithub is scripted for #{host}/#{repo_path}. " \
              "Scripted: #{githubs.keys.inspect}. A spec must never reach a real host."
      end

      recorded.asked << host
      recorded.api
    end

    begin
      yield
    ensure
      RepositorySourceFactory.builder = previous
    end
  end

  private def answer(url : String) : GithubRepositoryApi::Response
    case url
    when "#{GithubRepositoryApi::API_BASE}/repos/#{@repo_path}"
      GithubRepositoryApi::Response.new(@repository_status, repository_body)
    when .starts_with?("#{GithubRepositoryApi::API_BASE}/repos/#{@repo_path}/tags")
      GithubRepositoryApi::Response.new(@tags_status, tags_body)
    when .starts_with?("#{GithubRepositoryApi::API_BASE}/repos/#{@repo_path}/commits/")
      commit_body(url.rpartition('/').last)
    when .starts_with?("#{GithubRepositoryApi::RAW_BASE}/#{@repo_path}/")
      file_body(url.lchop("#{GithubRepositoryApi::RAW_BASE}/#{@repo_path}/"))
    else
      GithubRepositoryApi::Response.new(404, %({"message":"nothing recorded for #{url}"}))
    end
  end

  private def repository_body : String
    JSON.build do |json|
      json.object do
        @repository_fields.each do |name, value|
          json.field(name) { value.to_json(json) }
        end
      end
    end
  end

  private def tags_body : String
    JSON.build do |json|
      json.array do
        @tags.each do |tag|
          json.object do
            json.field "name", tag.name
            if sha = tag.sha
              json.field("commit") { json.object { json.field "sha", sha } }
            end
          end
        end
      end
    end
  end

  private def commit_body(sha : String) : GithubRepositoryApi::Response
    date = @commit_dates[sha]?
    return GithubRepositoryApi::Response.new(404, %({"message":"no commit #{sha}"})) unless date

    body = JSON.build do |json|
      json.object do
        json.field("commit") do
          json.object do
            json.field("committer") { json.object { json.field "date", date.to_rfc3339 } }
          end
        end
      end
    end

    GithubRepositoryApi::Response.new(200, body)
  end

  private def file_body(ref_and_path : String) : GithubRepositoryApi::Response
    status, content = @files[ref_and_path]? || {404, "404: Not Found"}
    GithubRepositoryApi::Response.new(status, content)
  end

  private def key(ref : String, path : String) : String
    "#{ref}/#{path}"
  end

  # JSON::Any holds Int64, not Int32, and a star count arriving as an Int32
  # would otherwise fail to typecheck against the one thing this body exists
  # to become.
  private def put(name : String, value : Int32?) : Nil
    return if value.nil?

    @repository_fields[name] = JSON::Any.new(value.to_i64)
  end

  private def put(name : String, value : String? | Bool? | Array(JSON::Any)?) : Nil
    return if value.nil?

    @repository_fields[name] = JSON::Any.new(value)
  end
end
