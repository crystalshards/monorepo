require "./base_worker"
require "../services/docs_builder"
require "../services/storage_service"

struct BuildDocsWorker < BaseJob
  def initialize(@shard_name : String, @version : String)
    @queue = "docs"
  end

  def perform
    log_info "Building docs for: #{@shard_name}@#{@version}"

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

    docs_url = build_and_upload_docs(shard, shard_version)

    if docs_url
      operation = SaveShard.new(shard)
      operation.documentation_url.value = docs_url
      operation.update!
      log_info "Successfully built docs for #{@shard_name}@#{@version}: #{docs_url}"
    else
      log_error "Failed to build docs for #{@shard_name}@#{@version}"
    end
  rescue ex : Exception
    log_error "Failed to build docs for #{@shard_name}@#{@version}", ex
    raise ex
  end

  private def build_and_upload_docs(shard : Shard, shard_version : ShardVersion) : String?
    temp_dir = File.tempname("shard_docs")
    Dir.mkdir_p(temp_dir)

    begin
      docs_dir = CrystalShards::DocsBuilder.build.generate_docs(
        shard.repository_url,
        shard_version.version,
        shard_version.commit_sha,
        temp_dir
      )
      return nil unless docs_dir

      upload_to_storage(shard, shard_version, docs_dir)
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  private def upload_to_storage(shard : Shard, shard_version : ShardVersion, docs_dir : String) : String
    storage = CrystalShards::StorageService.build
    uploaded_keys = storage.upload_docs(shard.name, shard_version.version, docs_dir)

    log_info "Uploaded #{uploaded_keys.size} documentation files to MinIO"
    "https://crystaldocs.org/#{shard.name}/#{shard_version.version}"
  rescue ex : Exception
    log_error "Error uploading docs to MinIO", ex
    raise ex
  end
end
