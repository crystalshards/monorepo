require "./base_worker"

class BuildDocsWorker < BaseJob
  param shard_name : String
  param version : String

  def perform
    log_info "Building docs for: #{@shard_name}@#{@version}"

    shard = ShardQuery.new.name(@shard_name).first?
    unless shard
      log_error "Shard not found: #{@shard_name}"
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
    minio_endpoint = ENV["MINIO_ENDPOINT"]? || "minio.infrastructure.svc.cluster.local:9000"
    minio_access_key = ENV["MINIO_ACCESS_KEY"]? || "minioadmin"
    minio_secret_key = ENV["MINIO_SECRET_KEY"]? || "minioadmin"
    bucket_name = "crystaldocs"

    docs_path = "#{shard.name}/#{shard_version.version}"

    Dir.glob("#{docs_dir}/**/*").each do |file_path|
      next unless File.file?(file_path)

      relative_path = file_path.sub("#{docs_dir}/", "")
      object_key = "#{docs_path}/#{relative_path}"

      upload_file_to_minio(
        endpoint: minio_endpoint,
        access_key: minio_access_key,
        secret_key: minio_secret_key,
        bucket: bucket_name,
        object_key: object_key,
        file_path: file_path
      )
    end

    log_info "Uploaded docs to MinIO: #{docs_path}"
    "https://crystaldocs.org/#{docs_path}"
  end

  private def upload_file_to_minio(endpoint : String, access_key : String, secret_key : String, bucket : String, object_key : String, file_path : String)
    http_client = HTTP::Client.new(endpoint.split(":")[0], endpoint.split(":")[1].to_i)

    file_content = File.read(file_path)
    content_type = guess_content_type(file_path)

    date = Time.utc.to_s("%Y%m%dT%H%M%SZ")
    authorization = "AWS4-HMAC-SHA256 Credential=#{access_key}/#{date[0..7]}/us-east-1/s3/aws4_request"

    headers = HTTP::Headers{
      "Host"           => endpoint,
      "Content-Type"   => content_type,
      "Content-Length" => file_content.bytesize.to_s,
      "Authorization"  => authorization,
    }

    response = http_client.put("/#{bucket}/#{object_key}", headers: headers, body: file_content)

    unless response.status_code == 200
      log_error "Failed to upload #{object_key}: #{response.status_code}"
    end
  rescue ex : Exception
    log_error "Error uploading file to MinIO: #{file_path}", ex
  end

  private def guess_content_type(file_path : String) : String
    case File.extname(file_path)
    when ".html"         then "text/html"
    when ".css"          then "text/css"
    when ".js"           then "application/javascript"
    when ".json"         then "application/json"
    when ".png"          then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".svg"          then "image/svg+xml"
    else                      "application/octet-stream"
    end
  end
end
