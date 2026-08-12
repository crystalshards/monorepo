require "./base_worker"

struct UpdateDependenciesWorker < BaseJob
  # The most dependency edges one version may contribute to the graph.
  #
  # A shard.yml comes from a repository anyone can publish, so the number of
  # entries in it is not a number this registry gets to trust. Uncapped, one
  # manifest declaring fifty thousand dependencies turns a single indexed shard
  # into fifty thousand rows and twice that many lookups, inside a sweep whose
  # whole design is a fixed cost per shard. The largest honest manifest in this
  # corpus declares well under fifty, so this bounds the pathological case
  # without touching a real one, and the truncation is logged rather than
  # silently changing what a shard appears to depend on.
  MAX_DEPENDENCIES = 200

  # One entry read out of a manifest, before it becomes a row.
  private record Declared, name : String, spec : JSON::Any, scope : String

  # Resolving dependencies parses the shard.yml already fetched during
  # indexing and writes rows. It executes no code from the shard, so it runs
  # where it was asked for rather than being handed to a queue.
  def self.enqueue(shard_name : String, version : String) : Nil
    CrystalShards::JobQueue.current.update_dependencies(shard_name, version)
  end

  # Replaces one version's dependency rows with what its stored manifest
  # declares, and answers how many edges that came to.
  #
  # A class method taking the row itself, because the two callers arrive
  # holding different things. The queue path has a name and a version string
  # and has to look both up. ShardIndexer has just written both records and is
  # holding them: making it re-resolve a name would spend two queries per shard
  # and would write nothing at all for a shard whose bare name is ambiguous,
  # which is precisely what ShardQuery#resolve returns nil for. One resolver,
  # entered from wherever the caller already stands.
  #
  # Nothing here reads a host. A dependency is matched against shards already
  # in this database, so the graph costs no GitHub rate limit.
  def self.resolve_for(shard_version : ShardVersion) : Int32
    declared = declared_dependencies(shard_version)
    written = 0

    AppDatabase.transaction do
      # The set is replaced wholesale, so a dependency dropped from a manifest
      # is dropped from the graph. Unconditional, because a manifest that
      # declares nothing still has to lose the rows the last one wrote:
      # returning early on an absent `dependencies:` key is how stale edges
      # outlive the manifest that created them.
      DependencyQuery.new.shard_version_id(shard_version.id).delete

      declared.each do |dependency|
        written += 1 if store_dependency(shard_version, dependency)
      end

      true
    end

    written
  end

  # Runtime first, then development. Either key may be absent and an absent one
  # is an empty set, not a reason to stop reading: a library with no runtime
  # dependencies and ameba in development still declares a dependency, and
  # ameba's dependents are understated for as long as that goes unrecorded.
  private def self.declared_dependencies(shard_version : ShardVersion) : Array(Declared)
    document = shard_version.metadata.try(&.as_h?)
    return [] of Declared unless document

    declared = [] of Declared
    seen = collect(declared, document["dependencies"]?, "runtime")
    seen += collect(declared, document["development_dependencies"]?, "development")

    if seen > declared.size
      Log.warn do
        "shard_version #{shard_version.id} declares #{seen} dependencies; " \
        "recording the first #{MAX_DEPENDENCIES} and ignoring the rest"
      end
    end

    declared
  end

  # Appends up to the cap and answers how many entries the manifest declared,
  # so the log can say what was left out. Stopping here rather than trimming
  # afterwards is what keeps a hostile manifest from being materialised in full
  # before it is cut down.
  private def self.collect(into : Array(Declared), value : JSON::Any?, scope : String) : Int32
    entries = value.try(&.as_h?)
    return 0 unless entries

    entries.each do |name, spec|
      break if into.size >= MAX_DEPENDENCIES

      into << Declared.new(name: name, spec: spec, scope: scope)
    end

    entries.size
  end

  # Written even when the name resolves to nothing. A manifest naming a shard
  # this registry has never seen is the common case rather than an error: the
  # requirement is recorded with a null dependent_shard_id, which says this
  # version depends on something called X without claiming to know which
  # repository X is. Discovering X later turns the row into an edge on the next
  # pass that reindexes this version.
  private def self.store_dependency(shard_version : ShardVersion, dependency : Declared) : Bool
    SaveDependency.create!(
      shard_version_id: shard_version.id,
      name: dependency.name,
      version_requirement: extract_version_requirement(dependency.spec),
      scope: dependency.scope,
      dependent_shard_id: resolve_dependent_shard(dependency).try(&.id)
    )
    true
  rescue ex : Avram::InvalidOperationError
    # A blank dependency name is the realistic case. Skipping the one entry
    # keeps the rest of the version's graph, and validation fails before any
    # SQL is issued, so the surrounding transaction is still usable.
    Log.warn { "Skipped dependency #{dependency.name.inspect} on shard_version #{shard_version.id}: #{ex.message}" }
    false
  end

  # A shard.yml dependency already says which host it comes from:
  #
  #   router:
  #     gitlab: acme/router
  #
  # So the edge is resolved from that source, which names one repository
  # exactly. Only when a dependency carries no source at all does this fall
  # back to the name, and then only when one shard answers to it. An
  # unresolvable dependency is stored with a null dependent_shard_id: the
  # requirement is still recorded, it simply does not claim to point at a
  # repository we cannot identify.
  private def self.resolve_dependent_shard(dependency : Declared) : Shard?
    if slug = dependency_slug(dependency.spec)
      return ShardQuery.new.canonical_slug(slug).first?
    end

    ShardQuery.new.resolve(dependency.name)
  end

  # Maps a dependency's source to a canonical slug. The shorthand keys are the
  # ones the shards tool itself understands.
  private def self.dependency_slug(dep_spec : JSON::Any) : String?
    spec = dep_spec.as_h?
    return nil unless spec

    {
      "github"    => "github.com",
      "gitlab"    => "gitlab.com",
      "bitbucket" => "bitbucket.org",
      "codeberg"  => "codeberg.org",
    }.each do |key, host|
      if path = spec[key]?.try(&.as_s?)
        return ShardIdentity.parse_url("https://#{host}/#{path}").try(&.canonical_slug)
      end
    end

    # A plain git source carries the whole URL.
    if git_url = spec["git"]?.try(&.as_s?)
      return ShardIdentity.parse_url(git_url).try(&.canonical_slug)
    end

    nil
  end

  private def self.extract_version_requirement(dep_spec : JSON::Any) : String
    case raw = dep_spec.raw
    when String then raw
    when Hash   then constraint(dep_spec["version"]?) || "*"
    else             "*"
    end
  end

  # A constraint is a string in every manifest that quotes it and a number in
  # the ones that do not, because `version: 1.0` is legal YAML and reads as a
  # float. Both mean the same thing to the shards tool, so both are recorded.
  # Reaching for as_s here instead would raise on the unquoted ones, and a
  # sweep reading three hundred arbitrary manifests will meet them.
  private def self.constraint(value : JSON::Any?) : String?
    return nil unless value

    case raw = value.raw
    when String  then raw.presence
    when Int64   then raw.to_s
    when Float64 then raw.to_s
    end
  end

  # @shard_name carries the canonical slug for anything crystalshards
  # enqueues; the field name is the wire format and does not change.
  def initialize(@shard_name : String, @version : String)
    @queue = "deps"
  end

  def perform
    log_info "Updating dependencies for: #{@shard_name}@#{@version}"

    shard = ShardQuery.new.resolve(@shard_name)
    unless shard
      log_error "No single shard in the registry answers to #{@shard_name}; dependencies untouched"
      return
    end

    shard_version = ShardVersionQuery.new
      .shard_id(shard.id)
      .version(@version)
      .first?

    unless shard_version
      log_error "Shard version not found: #{@shard_name}@#{@version}"
      return
    end

    written = UpdateDependenciesWorker.resolve_for(shard_version)
    log_info "Stored #{written} dependencies for #{@shard_name}@#{@version}"
  rescue ex : Exception
    log_error "Failed to update dependencies for #{@shard_name}@#{@version}", ex
    raise ex
  end
end
