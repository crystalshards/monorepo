require "./base_worker"

class UpdateDependenciesWorker < BaseJob
  param shard_name : String
  param version : String

  def perform
    log_info "Updating dependencies for: #{@shard_name}@#{@version}"

    shard = ShardQuery.new.name(@shard_name).first?
    unless shard
      log_error "Shard not found: #{@shard_name}"
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

    dependent_shard = ShardQuery.new.name(dep_name).first?

    SaveDependency.create do |operation|
      operation.shard_version_id.value = shard_version.id.not_nil!
      operation.name.value = dep_name
      operation.version_requirement.value = version_requirement
      operation.scope.value = scope
      operation.dependent_shard_id.value = dependent_shard.try(&.id)
    end
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
