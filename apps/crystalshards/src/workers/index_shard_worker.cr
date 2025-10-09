require "./base_worker"
require "../providers/provider_factory"

struct IndexShardWorker < BaseJob
  @[JSON::Field(ignore: true)]
  @provider : BaseProvider?

  def initialize(@shard_name : String, @version : String, @provider : BaseProvider? = nil)
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

    # Skip enqueueing jobs in test environment to avoid Redis connection
    unless LuckyEnv.test?
      UpdateDependenciesWorker.enqueue(
        shard_name: @shard_name.not_nil!,
        version: @version.not_nil!
      )

      BuildDocsWorker.enqueue(
        shard_name: @shard_name.not_nil!,
        version: @version.not_nil!
      )
    end

    log_info "Successfully indexed #{@shard_name}@#{@version}"
  rescue ex : Exception
    log_error "Failed to index #{@shard_name}@#{@version}", ex
    raise ex
  end

  private def fetch_and_parse_shard_yml(shard : Shard, shard_version : ShardVersion)
    provider = @provider || ProviderFactory.create(shard.repository_url)

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

    SaveShard.update!(shard,
      github_stars: metadata.stars,
      github_forks: metadata.forks,
      provider: provider.provider_name,
      repository_type: provider.repository_type,
      last_synced_at: Time.utc
    )

    log_info "Updated provider metadata for #{shard.name}"
  rescue ex : Exception
    log_error "Failed to update provider metadata", ex
  end

  private def update_from_shard_yml(shard : Shard, shard_version : ShardVersion, shard_yml : YAML::Any)
    description = shard_yml["description"]?.try(&.as_s?)
    license = shard_yml["license"]?.try(&.as_s?)
    homepage = shard_yml["homepage"]?.try(&.as_s?)
    crystal = shard_yml["crystal"]?.try(&.as_s?)

    # Update shard metadata from shard.yml
    operation = SaveShard.new(shard)
    operation.description.value = description if description
    operation.license.value = license if license
    operation.homepage_url.value = homepage if homepage
    operation.save!

    # Update shard version with crystal version and full metadata
    version_operation = SaveShardVersion.new(shard_version)
    version_operation.crystal_version.value = crystal if crystal
    version_operation.metadata.value = JSON.parse(shard_yml.to_json)
    version_operation.save!

    log_info "Updated shard metadata from shard.yml"
  end
end
