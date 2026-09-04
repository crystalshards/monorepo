require "../providers/repository_source_factory"
require "../workers/update_dependencies_worker"
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
    detail : String? = nil,
    dependencies : Int32 = 0 do
    def indexed? : Bool
      outcome == Outcome::Indexed
    end
  end

  README_FILENAMES = %w[README.md readme.md README.markdown Readme.md README.rst README]

  # No test seam of its own. RepositorySourceFactory already has one, and two
  # seams for one job is how a spec ends up proving a path production does not
  # take. Specs install RepositorySourceFactory.builder and restore it in an
  # `ensure`.

  STAMP_SQL = <<-SQL
    UPDATE shards
    SET index_attempted_at = COALESCE($1, index_attempted_at),
        index_error = $2,
        index_step = NULL,
        updated_at = NOW()
    WHERE id = $3
    SQL

  def self.index(shard : Shard) : Result
    new(shard).call
  end

  # When an index pass crashes rather than returning a Result (a database
  # constraint violation, a dropped connection, or an Avram validation error
  # from SaveShard), the shard row must not be left looking mid-flight.
  # This records the crash reason directly on the shard row, clears any
  # active index_step, and leaves index_attempted_at and indexed_at untouched.
  #
  # Uses the same targeted UPDATE as #stamp so that a row too malformed for
  # SaveShard can still record why the pass failed.
  def self.record_crash(shard : Shard, message : String) : Nil
    AppDatabase.exec(STAMP_SQL, nil, message, shard.id)
  rescue ex : Exception
    Log.warn(exception: ex) do
      "ShardIndexer: could not record crash for shard #{shard.id}"
    end
  end

  def self.record_crash(shard : Shard, ex : Exception) : Nil
    record_crash(shard, ex.message.presence || ex.class.name)
  end

  def initialize(@shard : Shard)
  end

  def call : Result
    # Every host the crawler can find, indexing can read. Discovery enumerates
    # github.com, gitlab.com, codeberg.org and bitbucket.org, and three of those
    # answer unauthenticated, so gating on GitHub alone would leave shards the
    # crawler had already found permanently blank for want of a credential none
    # of them need. Anything outside that list is recorded as unsupported rather
    # than left looking un-indexed forever, so the sweep's numbers describe
    # reality.
    host = @shard.host
    unless RepositorySourceFactory.supports?(host)
      claim
      detail = "#{host || "This row's host"} is not a host the registry can read"
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

    begin
      api = RepositorySourceFactory.for(host.not_nil!, repo_path)
    rescue ex : RepositorySourceFactory::UnsupportedHostError
      detail = ex.message || "This host has no reader"
      finish(error: detail)
      return Result.new(Outcome::Unsupported, @shard, detail: detail)
    end

    step(IndexSteps::READING)

    begin
      snapshot = api.fetch_snapshot
    rescue ex : RepositorySource::NotFound
      return mark_unavailable(ex.message || "The repository is no longer reachable")
    rescue ex : RepositorySource::Error
      detail = ex.message || "The repository could not be read"
      finish(error: detail)
      return Result.new(Outcome::Failed, @shard, detail: detail)
    end

    step(IndexSteps::MANIFEST)
    latest = VersionOrder.latest(snapshot.refs)
    content = latest ? fetch_content(api, latest, snapshot) : nil

    # Stored first, then resolved: the graph is written from a manifest that is
    # already committed, so a dependency failure cannot cost the shard the
    # content this pass just fetched.
    step(IndexSteps::RECORDING)
    indexed_version = store(snapshot, latest, content)

    step(IndexSteps::DEPENDENCIES)
    dependencies = resolve_dependencies(indexed_version, content)
    finish
    Result.new(
      Outcome::Indexed,
      @shard,
      versions: snapshot.refs.size,
      indexed_version: latest.try(&.version),
      dependencies: dependencies,
    )
  end

  # What one ref's fetch produced. `manifest_error` is a sentence for a reader,
  # never an exception name, because it is rendered on the version.
  #
  # `manifest_known` separates the two ways `manifest` ends up nil. The host
  # answering "there is no shard.yml here", or answering with one that does not
  # parse, are both facts about the repository at an immutable ref. The host
  # failing to answer is a fact about the fetch and says nothing about the ref
  # at all. Only the first kind may be written into the dependency graph.
  private record Content,
    ref : RepositorySnapshot::Ref,
    spec_yaml : String? = nil,
    manifest : ShardManifest? = nil,
    manifest_error : String? = nil,
    manifest_known : Bool = true,
    readme : String? = nil,
    committed_at : Time? = nil

  private def fetch_content(
    api : RepositorySource,
    ref : RepositorySnapshot::Ref,
    snapshot : RepositorySnapshot,
  ) : Content
    spec_yaml = nil
    manifest = nil
    manifest_error = nil
    manifest_known = true

    case result = api.fetch_file(ref.ref, "shard.yml")
    in RepositorySource::FileResult::Found
      spec_yaml = result.content
      case parsed = ShardManifest.parse(result.content)
      in ShardManifest then manifest = parsed
      in String        then manifest_error = parsed
      end
    in RepositorySource::FileResult::Absent
      # A real fact about the repository, not a gap in the registry. Discovery
      # found this repository BY its shard.yml, so an absent one at a tag means
      # the manifest was added after that tag was cut.
      manifest_error = ref.tag? ? "No shard.yml at tag #{ref.ref}." : "No shard.yml on branch #{ref.ref}."
    in RepositorySource::FileResult::Failed
      manifest_error = "shard.yml could not be fetched at #{ref.ref}: #{result.reason}."
      manifest_known = false
    end

    Content.new(
      ref: ref,
      spec_yaml: spec_yaml,
      manifest: manifest,
      manifest_error: manifest_error,
      manifest_known: manifest_known,
      readme: fetch_readme(api, ref),
      # One dated commit per shard, for the version actually being indexed.
      # Every other tag keeps the repository's pushed_at, because dating them
      # all costs one core request each.
      committed_at: ref.commit_sha.try { |sha| api.fetch_commit_date(sha) } || ref.committed_at || snapshot.pushed_at,
    )
  end

  private def fetch_readme(api : RepositorySource, ref : RepositorySnapshot::Ref) : String?
    README_FILENAMES.each do |filename|
      case result = api.fetch_file(ref.ref, filename)
      in RepositorySource::FileResult::Found then return result.content
      in RepositorySource::FileResult::Absent
        next
      in RepositorySource::FileResult::Failed
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
  #
  # Written with a targeted UPDATE rather than through SaveShard, and that is
  # the whole point. SaveShard requires host, owner, repo and canonical_slug,
  # which a legacy row predating host-qualified identity does not have, so
  # claiming through it raised before the row could be stamped. The row then
  # returned to the head of the queue on every single run: the exact poison
  # shard the claim-first ordering exists to prevent, caused by the claim.
  #
  # These three columns are the indexer's bookkeeping ABOUT a row, not the
  # shard's own data. They have to be writable even when the row itself is
  # malformed, because a row we cannot read is precisely the one that most needs
  # recording as attempted.
  private def claim : Nil
    stamp(index_attempted_at: Time.utc)
  end

  # The ordered steps an index pass moves through, written one at a time while
  # it runs so a visitor watching an unindexed shard sees it advance rather
  # than reading one sentence for the whole pass.
  #
  # Both the writer and the reader are in this app, unlike the documentation
  # build's equivalent, so there is one list and no vocabulary to keep in sync.
  module IndexSteps
    record Step, name : String, label : String, description : String

    READING      = "reading"
    MANIFEST     = "manifest"
    RECORDING    = "recording"
    DEPENDENCIES = "dependencies"

    # In the order `ShardIndexer#call` performs them.
    ALL = [
      Step.new(READING, "Reading the repository", "Fetching its tags and metadata."),
      Step.new(MANIFEST, "Reading shard.yml", "And the README, at the newest tag."),
      Step.new(RECORDING, "Recording versions", "Writing what the repository publishes."),
      Step.new(DEPENDENCIES, "Resolving dependencies", "Matching what it depends on to the registry."),
    ]

    def self.index_of(name : String?) : Int32?
      return nil if name.nil?

      ALL.index { |step| step.name == name }
    end
  end

  # Where this pass has got to, for the page that commissioned it.
  #
  # Never raises and never fails a pass. A step is a progress hint with no
  # durable meaning: `finish` clears it either way, and a pass whose steps were
  # all lost still records its outcome correctly. Losing an index pass in order
  # to report that it reached step three would be a strictly worse trade.
  private def step(name : String) : Nil
    AppDatabase.exec(
      "UPDATE shards SET index_step = $1, updated_at = NOW() WHERE id = $2",
      name,
      @shard.id
    )
  rescue ex : Exception
    Log.warn(exception: ex) do
      "ShardIndexer: could not record step #{name} for shard #{@shard.id}; " \
      "the pass is unaffected"
    end
  end

  # Same reasoning as claim: recording why a shard could not be indexed must not
  # require the shard to be well-formed enough to save.
  private def stamp(
    index_attempted_at : Time? = nil,
    index_error : String? = nil,
  ) : Nil
    # index_step is cleared here rather than set. Every path that stamps an
    # outcome is the end of the pass, so no progress may outlive it: a shard
    # left reading "Resolving dependencies" after the pass completed or failed
    # would show a visitor a step that is not happening.
    AppDatabase.exec(STAMP_SQL, index_attempted_at, index_error, @shard.id)

    if reloaded = ShardQuery.new.id(@shard.id).first?
      @shard = reloaded
    end
  end

  # Everything this pass learned, written together. Either the shard has its new
  # content and says so, or it has none of it and says that instead; there is no
  # state where the stamp claims success over half-written rows.
  private def store(
    snapshot : RepositorySnapshot,
    latest : RepositorySnapshot::Ref?,
    content : Content?,
  ) : ShardVersion?
    indexed_version = nil

    AppDatabase.transaction do
      indexed_version = store_versions(snapshot, latest, content)
      store_repository(snapshot, latest, content)
      true
    end

    indexed_version
  end

  # The dependency graph, written from the manifest this pass just stored.
  #
  # Deliberately after that transaction commits, and deliberately unable to
  # fail the shard. An edge naming a shard the registry has never seen is
  # normal and is stored with a null dependent_shard_id rather than skipped;
  # anything worse than that is a graph problem, and throwing away a shard's
  # freshly fetched content over one would be a poor trade. The whole set is
  # recomputed on the next pass regardless.
  #
  # Skipped entirely when the host did not answer for shard.yml. A ref is
  # immutable, so a manifest read successfully yesterday still says what it
  # said; a 500 from the file endpoint today is news about the host, not about
  # the ref. Replacing the graph on it would delete true edges over a bad
  # second and drop the shard out of every dependent count until the next pass
  # happened to succeed. An ABSENT manifest is the opposite: the host answered,
  # this ref really declares nothing, and the old edges have to go.
  #
  # Bounded three ways. Only the one version whose manifest was fetched is
  # resolved, so a shard with 65 tags is still one unit of work rather than 65.
  # The resolver caps how many entries a single manifest may contribute. And
  # nothing here reads a host: a dependency is matched against shards already
  # in this database, so the graph spends no GitHub rate limit.
  private def resolve_dependencies(shard_version : ShardVersion?, content : Content?) : Int32
    return 0 unless shard_version && content

    unless content.manifest_known
      Log.info { "Left #{@shard.canonical_slug} dependency edges alone: #{content.manifest_error}" }
      return 0
    end

    UpdateDependenciesWorker.resolve_for(shard_version)
  rescue ex : Exception
    Log.warn(exception: ex) { "Dependencies for #{@shard.canonical_slug} could not be resolved" }
    0
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
  # Answers the row for the version whose manifest was fetched, because that is
  # the one whose dependency edges are resolved once this transaction commits.
  private def store_versions(
    snapshot : RepositorySnapshot,
    latest : RepositorySnapshot::Ref?,
    content : Content?,
  ) : ShardVersion?
    shard_id = @shard.id
    existing = ShardVersionQuery.new.shard_id(shard_id).to_a.index_by(&.version)
    indexed_version = nil

    snapshot.refs.each do |ref|
      is_latest = latest && ref.version == latest.version
      row = existing[ref.version]?

      saved = if row
                update_version(row, ref, is_latest ? content : nil)
              else
                create_version(shard_id, ref, is_latest ? content : nil)
              end

      indexed_version = saved if is_latest
    end

    indexed_version
  end

  private def create_version(shard_id : Int64, ref : RepositorySnapshot::Ref, content : Content?) : ShardVersion?
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
    nil
  end

  private def update_version(row : ShardVersion, ref : RepositorySnapshot::Ref, content : Content?) : ShardVersion?
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
    nil
  end

  # Only the version that was actually fetched gets manifest fields written.
  # Passing nil leaves an older version's stored manifest exactly as it was.
  private def apply_content(operation : SaveShardVersion, content : Content?) : Nil
    return unless content

    operation.spec_error.value = content.manifest_error

    # The host never answered for shard.yml, so nothing was learned about this
    # ref and nothing derived from its manifest is overwritten. The stored
    # manifest stays, and so do the dependency edges resolved from it, which is
    # what makes that preservation durable: a later UpdateDependenciesWorker
    # run reads this same row, and had it been nulled here it would delete
    # every edge on the spot. Only the error is new.
    #
    # Crucially, indexed_at is only stamped when the manifest is known.
    # ShardVersion#indexed? drives reader-facing copy: when true, the page
    # reports "This version declares no dependencies.", and when false,
    # "Unknown: the shard.yml for this version has not been read yet." Stamping
    # it on a failed fetch makes the page state, as fact, that a shard declares
    # no dependencies.
    return unless content.manifest_known

    operation.indexed_at.value = Time.utc

    operation.spec_yaml.value = content.spec_yaml

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
    operation.index_step.value = nil
    @shard = operation.update!
    Result.new(Outcome::Unavailable, @shard, detail: reason)
  end

  private def finish(error : String? = nil) : Nil
    stamp(index_error: error)
  end
end
