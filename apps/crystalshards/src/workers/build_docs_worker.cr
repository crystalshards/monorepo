require "./base_worker"
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
      SaveShard.update(shard) do |operation|
        operation.documentation_url.value = docs_url
      end
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
      clone_repository(shard.repository_url, temp_dir)
      checkout_version(temp_dir, shard_version)

      install_dependencies(temp_dir)

      docs_dir = build_docs(temp_dir)
      return nil unless docs_dir

      upload_to_storage(shard, shard_version, docs_dir)
    ensure
      FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
    end
  end

  private def clone_repository(repo_url : String, target_dir : String)
    cmd = "git clone --depth 1 #{repo_url} #{target_dir}"
    output = `#{cmd} 2>&1`

    unless $?.success?
      raise "Failed to clone repository: #{output}"
    end

    log_info "Cloned repository for docs build"
  end

  private def checkout_version(repo_dir : String, shard_version : ShardVersion)
    if commit_sha = shard_version.commit_sha
      cmd = "cd #{repo_dir} && git fetch --depth 1 origin #{commit_sha} && git checkout #{commit_sha}"
    else
      cmd = "cd #{repo_dir} && git fetch --depth 1 origin tag #{shard_version.version} && git checkout #{shard_version.version}"
    end

    output = `#{cmd} 2>&1`

    unless $?.success?
      log_info "Could not checkout specific version, using HEAD"
    end
  end

  private def install_dependencies(repo_dir : String)
    cmd = "cd #{repo_dir} && shards install --ignore-crystal-version 2>&1"
    output = `#{cmd}`

    if $?.success?
      log_info "Installed shard dependencies"
    else
      log_info "Could not install dependencies, continuing anyway: #{output}"
    end
  end

  private def build_docs(repo_dir : String) : String?
    docs_output = File.join(repo_dir, "docs")

    cmd = "cd #{repo_dir} && crystal docs --output=#{docs_output} 2>&1"
    output = `#{cmd}`

    unless $?.success?
      log_error "Failed to build docs: #{output}"
      return nil
    end

    unless Dir.exists?(docs_output)
      log_error "Docs directory not created"
      return nil
    end

    log_info "Built documentation successfully"
    docs_output
  end

  private def upload_to_storage(shard : Shard, shard_version : ShardVersion, docs_dir : String) : String
    storage = CrystalShards::StorageService.new
    uploaded_keys = storage.upload_docs(shard.name, shard_version.version, docs_dir)

    log_info "Uploaded #{uploaded_keys.size} documentation files to MinIO"
    "https://crystaldocs.org/#{shard.name}/#{shard_version.version}"
  rescue ex : Exception
    log_error "Error uploading docs to MinIO", ex
    raise ex
  end
end
