require "./base_worker"

class IndexShardWorker < BaseJob
  param shard_name : String
  param version : String

  def perform
    log_info "Indexing shard: #{@shard_name}@#{@version}"

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

    fetch_and_parse_shard_yml(shard, shard_version)
    extract_metadata(shard, shard_version)

    UpdateDependenciesWorker.new(
      shard_name: @shard_name,
      version: @version
    ).enqueue

    BuildDocsWorker.new(
      shard_name: @shard_name,
      version: @version
    ).enqueue

    log_info "Successfully indexed #{@shard_name}@#{@version}"
  rescue ex : Exception
    log_error "Failed to index #{@shard_name}@#{@version}", ex
    raise ex
  end

  private def fetch_and_parse_shard_yml(shard : Shard, shard_version : ShardVersion)
    repo_url = shard.repository_url

    temp_dir = File.tempname("shard_index")
    Dir.mkdir_p(temp_dir)

    begin
      clone_repository(repo_url, temp_dir)
      checkout_version(temp_dir, shard_version)

      shard_yml_path = File.join(temp_dir, "shard.yml")
      unless File.exists?(shard_yml_path)
        log_error "shard.yml not found in repository"
        return
      end

      shard_yml = YAML.parse(File.read(shard_yml_path))
      update_from_shard_yml(shard, shard_version, shard_yml)
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

    log_info "Cloned repository: #{repo_url}"
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

  private def extract_metadata(shard : Shard, shard_version : ShardVersion)
    if shard.repository_url.includes?("github.com")
      fetch_github_metadata(shard)
    end
  end

  private def fetch_github_metadata(shard : Shard)
    repo_path = extract_github_repo_path(shard.repository_url)
    return unless repo_path

    github_api_url = "https://api.github.com/repos/#{repo_path}"

    response = HTTP::Client.get(github_api_url)
    return unless response.status_code == 200

    data = JSON.parse(response.body)

    SaveShard.update(shard) do |operation|
      operation.github_stars.value = data["stargazers_count"]?.try(&.as_i?)
      operation.github_forks.value = data["forks_count"]?.try(&.as_i?)
      operation.last_synced_at.value = Time.utc
    end

    log_info "Updated GitHub metadata for #{shard.name}"
  rescue ex : Exception
    log_error "Failed to fetch GitHub metadata", ex
  end

  private def extract_github_repo_path(url : String) : String?
    if match = url.match(/github\.com[\/:]([^\/]+\/[^\/\.]+)/)
      match[1]
    end
  end
end
