require "./base_worker"

struct UpdateDependenciesWorker < BaseJob
  # @shard_name carries the canonical slug for anything crystalshards
  # enqueues; the field name is the queue's wire format and does not change.
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
      .shard_id(shard.id.not_nil!)
      .version(@version)
      .first?

    unless shard_version
      log_error "Shard version not found: #{@shard_name}@#{@version}"
      return
    end

    parse_and_store_dependencies(shard, shard_version)
    log_info "Successfully updated dependencies for #{@shard_name}@#{@version}"
  rescue ex : Exception
    log_error "Failed to update dependencies for #{@shard_name}@#{@version}", ex
    raise ex
  end

  private def parse_and_store_dependencies(shard : Shard, shard_version : ShardVersion)
    metadata = shard_version.metadata
    return unless metadata

    dependencies = metadata["dependencies"]?.try(&.as_h?)
    return unless dependencies

    DependencyQuery.new.shard_version_id(shard_version.id.not_nil!).delete

    dependencies.each do |dep_name, dep_spec|
      store_dependency(shard_version, dep_name.to_s, dep_spec, "runtime")
    end

    dev_dependencies = metadata["development_dependencies"]?.try(&.as_h?)
    if dev_dependencies
      dev_dependencies.each do |dep_name, dep_spec|
        store_dependency(shard_version, dep_name.to_s, dep_spec, "development")
      end
    end

    log_info "Stored #{dependencies.size} dependencies"
  end

  private def store_dependency(shard_version : ShardVersion, dep_name : String, dep_spec : JSON::Any, scope : String)
    version_requirement = extract_version_requirement(dep_spec)

    SaveDependency.create!(
      shard_version_id: shard_version.id.not_nil!,
      name: dep_name,
      version_requirement: version_requirement,
      scope: scope,
      dependent_shard_id: resolve_dependent_shard(dep_name, dep_spec).try(&.id)
    )
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
  private def resolve_dependent_shard(dep_name : String, dep_spec : JSON::Any) : Shard?
    if slug = dependency_slug(dep_spec)
      return ShardQuery.new.canonical_slug(slug).first?
    end

    ShardQuery.new.resolve(dep_name)
  end

  # Maps a dependency's source to a canonical slug. The shorthand keys are the
  # ones the shards tool itself understands.
  private def dependency_slug(dep_spec : JSON::Any) : String?
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

  private def extract_version_requirement(dep_spec : JSON::Any) : String
    case dep_spec.raw
    when String
      dep_spec.as_s
    when Hash
      if version = dep_spec["version"]?
        version.as_s
      else
        "*"
      end
    else
      "*"
    end
  end
end
