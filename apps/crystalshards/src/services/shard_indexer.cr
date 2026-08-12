require "../providers/github_repository_api"
require "./shard_manifest"
require "./version_order"

# Turns a discovered shard into a shard with content.
#
# Discovery writes identity and stops, which is why a shard page can be reached
# and shows nothing. This fetches what the page needs: repository facts, the tag
# list as version rows, the latest version's manifest parsed, and the README.
#
# The shape of one shard's pass:
#
#   1. claim      index_attempted_at, committed on its own before any fetch
#   2. fetch      every HTTP call, outside any transaction
#   3. store      one transaction: repository facts, version rows, manifest,
#                 README, and the outcome stamp together
#
# Claiming first is deliberate. A process killed mid-shard leaves a row with
# index_attempted_at set and both indexed_at and index_error nil, which reads as
# exactly what it is: attempted, outcome unknown. That row sorts to the BACK of
# the queue rather than the front, so a repository that reliably kills the
# process cannot block every other shard behind it, and it is still picked up on
# a later pass because the queue is ordered by staleness and eventually returns
# to it. The alternative, stamping after the writes, turns one poison repository
# into a permanently stuck sweep.
#
# Fetching outside the transaction matters just as much: holding a Postgres
# transaction open across several seconds of HTTP would pin a connection per
# shard for the whole pass.
class ShardIndexer
  # Where a shard ended up. Recorded rather than logged, because a sweep's
  # summary is the only place anyone sees why 217 shards did or did not get
  # content.
  enum Outcome
    Indexed
    # The repository is gone, renamed, or private. The row is marked
    # unavailable; it is not deleted, because dependency edges and inbound
    # links still point at it and repositories come back.
    Unavailable
    # The fetch failed in a way a later pass may succeed at.
    Failed
    # Not a host this indexer can read. Recorded so the count is honest rather
    # than the shard silently never gaining content.
    Unsupported
  end

  record Result,
    outcome : Outcome,
    shard : Shard,
    versions : Int32 = 0,
    indexed_version : String? = nil,
    detail : String? = nil do
    def indexed? : Bool
      outcome == Outcome::Indexed
    end
  end

  README_FILENAMES = %w[README.md readme.md README.markdown Readme.md README.rst README]

  # Test seam. Specs install a builder returning an api driven from fixtures, so
  # the whole class runs with no network, and must restore it in an `ensure`.
  class_property api_builder : Proc(String, GithubRepositoryApi)? = nil

  def self.build_api(repo_path : String) : GithubRepositoryApi
    if builder = @@api_builder
      return builder.call(repo_path)
    end

    GithubRepositoryApi.new(repo_path, token: GithubRepositoryApi.token_from_env)
  end

  def self.index(shard : Shard) : Result
    new(shard).call
  end

  def initialize(@shard : Shard)
  end

  def call : Result
    # Only GitHub is readable this way today. Everything else is recorded as
    # unsupported rather than left looking un-indexed forever, so the sweep's
    # numbers describe reality.
    unless @shard.host == "github.com"
      claim
      detail = "#{@shard.host} is not a host this indexer can read yet"
      finish(error: detail)
      return Result.new(Outcome::Unsupported, @shard, detail: detail)
    end

    repo_path = @shard.repo_path
    unless repo_path
      claim
      detail = "This row has no owner/repo identity, so there is nothing to fetch"
      finish(error: detail)
      return Result.new(Outcome::Failed, @shard, detail: detail)
    end

    claim
    api = ShardIndexer.build_api(repo_path)

    begin
      snapshot = api.fetch_snapshot
    rescue ex : GithubRepositoryApi::NotFound
      return mark_unavailable(ex.message || "The repository is no longer reachable")
    rescue ex : GithubRepositoryApi::Error
      detail = ex.message || "The repository could not be read"
      finish(error: detail)
      return Result.new(Outcome::Failed, @shard, detail: detail)
    end

    latest = VersionOrder.latest(snapshot.refs)
    content = latest ? fetch_content(api, latest, snapshot) : nil

    store(snapshot, latest, content)

    Result.new(
      Outcome::Indexed,
      @shard,
      versions: snapshot.refs.size,
      indexed_version: latest.try(&.version),
    )
  end

  # What one ref's fetch produced. `manifest_error` is a sentence for a reader,
  # never an exception name, because it is rendered on the version.
  private record Content,
    ref : RepositorySnapshot::Ref,
    spec_yaml : String? = nil,
    manifest : ShardManifest? = nil,
    manifest_error : String? = nil,
    readme : String? = nil,
    committed_at : Time? = nil

  private def fetch_content(
    api : GithubRepositoryApi,
    ref : RepositorySnapshot::Ref,
    snapshot : RepositorySnapshot,
  ) : Content
    spec_yaml = nil
    manifest = nil
    manifest_error = nil

    case result = api.fetch_file(ref.ref, "shard.yml")
    in GithubRepositoryApi::FileResult::Found
      spec_yaml = result.content
      case parsed = ShardManifest.parse(result.content)
      in ShardManifest then manifest = parsed
      in String        then manifest_error = parsed
      end
    in GithubRepositoryApi::FileResult::Absent
      # A real fact about the repository, not a gap in the registry. Discovery
      # found this repository BY its shard.yml, so an absent one at a tag means
      # the manifest was added after that tag was cut.
      manifest_error = ref.tag? ? "No shard.yml at tag #{ref.ref}." : "No shard.yml on branch #{ref.ref}."
    in GithubRepositoryApi::FileResult::Failed
      manifest_error = "shard.yml could not be fetched at #{ref.ref}: #{result.reason}."
    end

    Content.new(
      ref: ref,
      spec_yaml: spec_yaml,
      manifest: manifest,
      manifest_error: manifest_error,
      readme: fetch_readme(api, ref),
      # One dated commit per shard, for the version actually being indexed.
      # Every other tag keeps the repository's pushed_at, because dating them
      # all costs one core request each.
      committed_at: ref.commit_sha.try { |sha| api.fetch_commit_date(sha) } || ref.committed_at || snapshot.pushed_at,
    )
  end

  private def fetch_readme(api : GithubRepositoryApi, ref : RepositorySnapshot::Ref) : String?
    README_FILENAMES.each do |filename|
      case result = api.fetch_file(ref.ref, filename)
      in GithubRepositoryApi::FileResult::Found then return result.content
      in GithubRepositoryApi::FileResult::Absent
        next
      in GithubRepositoryApi::FileResult::Failed
        # A failed README fetch is not worth failing the shard over, and not
        # worth trying five more filenames against a host that just errored.
        Log.debug { "README fetch failed for #{@shard.canonical_slug} at #{ref.ref}: #{result.reason}" }
        return nil
      end
    end

    nil
  end

  # Claimed before any fetch and committed on its own, so a crash cannot leave
  # the queue pointing at a shard it already spent requests on.
  private def claim : Nil
    operation = SaveShard.new(@shard)
    operation.index_attempted_at.value = Time.utc
    @shard = operation.update!
  end

  # Everything this pass learned, written together. Either the shard has its new
  # content and says so, or it has none of it and says that instead; there is no
  # state where the stamp claims success over half-written rows.
  private def store(
    snapshot : RepositorySnapshot,
    latest : RepositorySnapshot::Ref?,
    content : Content?,
  ) : Nil
    AppDatabase.transaction do
      store_versions(snapshot, latest, content)
      store_repository(snapshot, latest, content)
      true
    end
  end

  private def store_repository(
    snapshot : RepositorySnapshot,
    latest : RepositorySnapshot::Ref?,
    content : Content?,
  ) : Nil
    operation = SaveShard.new(@shard)

    # NULL means "not fetched", never zero. A permanent 0 star count reads as
    # "nobody uses this", which is a different and wrong claim.
    operation.github_stars.value = snapshot.stars if snapshot.stars
    operation.github_forks.value = snapshot.forks if snapshot.forks
    operation.topics.value = snapshot.topics
    operation.default_branch.value = snapshot.default_branch if snapshot.default_branch
    operation.pushed_at.value = snapshot.pushed_at if snapshot.pushed_at
    operation.archived.value = snapshot.archived unless snapshot.archived.nil?
    operation.last_synced_at.value = Time.utc

    # The repository's own description is the one a reader recognises, but a
    # manifest that supplies one is more specific about the shard as a library.
    if description = content.try(&.manifest).try(&.description) || snapshot.description
      operation.description.value = description
    end

    if homepage = content.try(&.manifest).try(&.homepage) || snapshot.homepage
      operation.homepage_url.value = homepage
    end

    # The manifest's licence is the shard's own claim; the repository's detected
    # licence is GitHub reading the LICENSE file. The shard's claim wins.
    if license = content.try(&.manifest).try(&.license) || snapshot.license
      operation.license.value = license
    end

    if readme = content.try(&.readme)
      operation.readme_content.value = readme
    end

    operation.latest_version.value = latest.try(&.version)
    operation.indexed_at.value = Time.utc
    operation.index_error.value = nil
    # A repository that answered is a repository that is there.
    operation.unavailable_at.value = nil

    @shard = operation.update!
  end

  # Every ref becomes a row, so a page can list versions rather than showing
  # only the newest. Only the latest gets its manifest fetched; the rest carry
  # ref, sha and a nil indexed_at, which is the signal a page uses to offer
  # fetching an older version on demand.
  private def store_versions(
    snapshot : RepositorySnapshot,
    latest : RepositorySnapshot::Ref?,
    content : Content?,
  ) : Nil
    shard_id = @shard.id
    existing = ShardVersionQuery.new.shard_id(shard_id).to_a.index_by(&.version)

    snapshot.refs.each do |ref|
      is_latest = latest && ref.version == latest.version
      row = existing[ref.version]?

      if row
        update_version(row, ref, is_latest ? content : nil)
      else
        create_version(shard_id, ref, is_latest ? content : nil)
      end
    end
  end

  private def create_version(shard_id : Int64, ref : RepositorySnapshot::Ref, content : Content?) : Nil
    operation = SaveShardVersion.new
    operation.shard_id.value = shard_id
    operation.version.value = ref.version
    operation.ref.value = ref.ref
    operation.source.value = ref.source
    operation.commit_sha.value = ref.commit_sha
    operation.released_at.value = content.try(&.committed_at) || ref.committed_at || Time.utc
    operation.yanked.value = false
    apply_content(operation, content)
    operation.save!
  rescue ex : Avram::InvalidOperationError
    # One bad ref must not cost a shard its other versions. A tag whose name
    # collides with a row written by an older code path is the realistic case.
    Log.warn { "Skipped #{@shard.canonical_slug}@#{ref.version}: #{ex.message}" }
  end

  private def update_version(row : ShardVersion, ref : RepositorySnapshot::Ref, content : Content?) : Nil
    operation = SaveShardVersion.new(row)
    operation.ref.value = ref.ref
    operation.source.value = ref.source
    operation.commit_sha.value = ref.commit_sha if ref.commit_sha
    # An already-dated version keeps its date: re-reading the tag list must not
    # overwrite a real commit date with the repository's pushed_at fallback.
    if committed_at = content.try(&.committed_at)
      operation.released_at.value = committed_at
    end
    apply_content(operation, content)
    operation.update!
  rescue ex : Avram::InvalidOperationError
    Log.warn { "Could not update #{@shard.canonical_slug}@#{ref.version}: #{ex.message}" }
  end

  # Only the version that was actually fetched gets manifest fields written.
  # Passing nil leaves an older version's stored manifest exactly as it was.
  private def apply_content(operation : SaveShardVersion, content : Content?) : Nil
    return unless content

    operation.spec_yaml.value = content.spec_yaml
    operation.spec_error.value = content.manifest_error
    operation.indexed_at.value = Time.utc

    if manifest = content.manifest
      operation.crystal_version.value = manifest.crystal
      operation.metadata.value = manifest.document
      operation.targets.value = manifest.targets
      operation.executables.value = manifest.executables
    else
      # A version whose manifest could not be read must not keep a previous
      # pass's parse: that would show a manifest the tag does not have.
      operation.crystal_version.value = nil
      operation.metadata.value = nil
      operation.targets.value = nil
      operation.executables.value = nil
    end
  end

  private def mark_unavailable(reason : String) : Result
    operation = SaveShard.new(@shard)
    operation.unavailable_at.value = Time.utc
    operation.index_error.value = reason
    operation.indexed_at.value = nil
    @shard = operation.update!

    Result.new(Outcome::Unavailable, @shard, detail: reason)
  end

  private def finish(error : String?) : Nil
    operation = SaveShard.new(@shard)
    operation.index_error.value = error
    @shard = operation.update!
  end
end
