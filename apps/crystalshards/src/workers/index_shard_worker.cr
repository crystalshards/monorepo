require "./base_worker"
require "../providers/provider_factory"

struct IndexShardWorker < BaseJob
  # The jobs this worker chains once a shard version has been indexed.
  #
  # Documentation is deliberately NOT one of them. It is built on first
  # request, which is the contract CrystalDocs::DocBuildRequests is written
  # around: "built on first request, rather than eagerly for every published
  # version of every shard".
  #
  # Chaining it here broke that in the most expensive way available. Every
  # version of every shard the sweep indexed put a build on the queue, so a
  # registry of thousands of shards queued tens of thousands of compiles, and
  # the builder runs a handful at a time. A reader opening a page joined the
  # back of that queue and waited behind the entire catalogue, which is what
  # "still no docs" looked like from outside: the pipeline working perfectly
  # and nobody's page ever reaching the front.
  #
  # It also spends the compile on documentation nobody has asked to read, for
  # every version ever published, forever.
  enum Followup
    UpdateDependencies
  end

  # Test seam. Every follow-up job is scheduled through this proc, which
  # defaults to the real dispatch so production keeps working unchanged when
  # nothing installs a fake. Specs swap it out to observe chaining without
  # running the follow-ups, and must restore it in an `ensure`.
  class_property dispatcher : Proc(Followup, String, String, Nil) = ->(followup : Followup, shard_name : String, version : String) {
    case followup
    in Followup::UpdateDependencies
      UpdateDependenciesWorker.enqueue(shard_name: shard_name, version: version)
    end
    nil
  }

  # Indexing reads the shard's host and writes the registry. It executes no
  # code from the shard, so it runs wherever it was asked for rather than
  # being handed to a queue.
  def self.enqueue(shard_name : String, version : String) : Nil
    CrystalShards::JobQueue.current.index_shard(shard_name, version)
  end

  # @shard_name is the wire field name the queue already carries, so it stays.
  # Its VALUE is the canonical slug ("github.com/kemalcr/kemal") for everything
  # crystalshards enqueues: two shards named "router" on different hosts would
  # otherwise be one indistinguishable job. Follow-ups are chained with the
  # same key, so the identity travels the whole pipeline.
  def initialize(@shard_name : String, @version : String)
    @queue = "index"
  end

  def perform
    log_info "Indexing shard: #{@shard_name}@#{@version}"

    shard = ShardQuery.new.resolve(@shard_name)
    unless shard
      log_error "No single shard in the registry answers to #{@shard_name}; nothing indexed"
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

    manifest_stored = fetch_and_parse_shard_yml(shard, shard_version)
    unless manifest_stored
      log_error "Failed to index #{@shard_name}@#{@version}: shard.yml could not be fetched; no manifest stored"
      return
    end

    # Follow-ups are keyed on the identity we just resolved, never on whatever
    # string arrived. A job that came in under a bare name still chains as
    # "github.com/owner/repo", so the rest of the pipeline cannot land on a
    # different shard of the same name.
    dispatch = @@dispatcher
    followup_key = shard.canonical_slug || @shard_name
    dispatch.call(Followup::UpdateDependencies, followup_key, @version)

    log_info "Successfully indexed #{@shard_name}@#{@version}"
  rescue ex : Exception
    log_error "Failed to index #{@shard_name}@#{@version}", ex
    raise ex
  end

  private def fetch_and_parse_shard_yml(shard : Shard, shard_version : ShardVersion) : Bool
    provider = ProviderFactory.create(shard.repository_url)

    shard_yml = provider.fetch_shard_yml(shard_version.version)
    unless shard_yml
      log_error "Could not fetch shard.yml from repository"
      return false
    end

    update_from_shard_yml(shard, shard_version, shard_yml)

    update_readme(shard, provider, shard_version.version)

    if provider.supports_api?
      update_provider_metadata(shard, provider)
    end

    true
  end

  private def update_readme(shard : Shard, provider : BaseProvider, version : String)
    readme = provider.fetch_readme(version)
    return unless readme

    operation = SaveShard.new(shard)
    operation.readme_content.value = readme
    operation.update!

    log_info "Stored README for #{shard.name}"
  rescue ex : Exception
    log_error "Failed to fetch README for #{shard.name}", ex
  end

  private def update_provider_metadata(shard : Shard, provider : BaseProvider)
    metadata = provider.fetch_metadata
    return unless metadata

    operation = SaveShard.new(shard)
    operation.github_stars.value = metadata.stars if metadata.stars
    operation.github_forks.value = metadata.forks if metadata.forks
    operation.provider.value = provider.provider_name
    operation.repository_type.value = provider.repository_type
    operation.last_synced_at.value = Time.utc
    operation.update!

    log_info "Updated provider metadata for #{shard.name}"
  rescue ex : Exception
    log_error "Failed to update provider metadata", ex
  end

  private def update_from_shard_yml(shard : Shard, shard_version : ShardVersion, shard_yml : YAML::Any)
    description = shard_yml["description"]?.try(&.as_s?)
    license = shard_yml["license"]?.try(&.as_s?)
    homepage = shard_yml["homepage"]?.try(&.as_s?)
    crystal = shard_yml["crystal"]?.try(&.as_s?)

    shard_operation = SaveShard.new(shard)
    shard_operation.description.value = description if description
    shard_operation.license.value = license if license
    shard_operation.homepage_url.value = homepage if homepage
    shard_operation.update!

    version_operation = SaveShardVersion.new(shard_version)
    version_operation.crystal_version.value = crystal if crystal
    version_operation.metadata.value = JSON.parse(shard_yml.to_json)
    version_operation.update!

    log_info "Updated shard metadata from shard.yml"
  end
end
