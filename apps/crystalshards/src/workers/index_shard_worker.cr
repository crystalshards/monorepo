require "./base_worker"
require "../providers/provider_factory"

struct IndexShardWorker < BaseJob
  def initialize(@shard_name : String, @version : String)
    @queue = "index"
  end

  def perform
    log_info "Indexing shard: #{@shard_name}@#{@version}"

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

    fetch_and_parse_shard_yml(shard, shard_version)

    UpdateDependenciesWorker.enqueue(
      shard_name: @shard_name.not_nil!,
      version: @version.not_nil!
    )

    BuildDocsWorker.enqueue(
      shard_name: @shard_name.not_nil!,
      version: @version.not_nil!
    )

    log_info "Successfully indexed #{@shard_name}@#{@version}"
  rescue ex : Exception
    log_error "Failed to index #{@shard_name}@#{@version}", ex
    raise ex
  end

  private def fetch_and_parse_shard_yml(shard : Shard, shard_version : ShardVersion)
    provider = ProviderFactory.create(shard.repository_url)

    shard_yml = provider.fetch_shard_yml(shard_version.version)
    unless shard_yml
      log_error "Could not fetch shard.yml from repository"
      return
    end

    update_from_shard_yml(shard, shard_version, shard_yml)

    if provider.supports_api?
      update_provider_metadata(shard, provider)
    end
  end

  private def update_provider_metadata(shard : Shard, provider : BaseProvider)
    metadata = provider.fetch_metadata
    return unless metadata

    SaveShard.update(shard) do |operation|
      operation.github_stars.value = metadata.stars if metadata.stars
      operation.github_forks.value = metadata.forks if metadata.forks
      operation.provider.value = provider.provider_name
      operation.repository_type.value = provider.repository_type
      operation.last_synced_at.value = Time.utc
    end

    log_info "Updated provider metadata for #{shard.name}"
  rescue ex : Exception
    log_error "Failed to update provider metadata", ex
  end

  private def update_from_shard_yml(shard : Shard, shard_version : ShardVersion, shard_yml : YAML::Any)
    description = shard_yml["description"]?.try(&.as_s?)
    license = shard_yml["license"]?.try(&.as_s?)
    homepage = shard_yml["homepage"]?.try(&.as_s?)
    crystal = shard_yml["crystal"]?.try(&.as_s?)

    SaveShard.update(shard) do |operation|
      operation.description.value = description if description
      operation.license.value = license if license
      operation.homepage_url.value = homepage if homepage
    end

    SaveShardVersion.update(shard_version) do |operation|
      operation.crystal_version.value = crystal if crystal
      operation.metadata.value = JSON.parse(shard_yml.to_json)
    end

    log_info "Updated shard metadata from shard.yml"
  end
end
