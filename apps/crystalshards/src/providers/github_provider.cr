require "./base_provider"
require "http/client"
require "json"

class GithubProvider < BaseProvider
  GITHUB_API_BASE = "https://api.github.com"
  GITHUB_RAW_BASE = "https://raw.githubusercontent.com"

  def fetch_shard_yml(version : String? = nil) : YAML::Any?
    repo_path = extract_repo_path
    return nil unless repo_path

    candidate_refs(version).each do |ref|
      response = HTTP::Client.get("#{GITHUB_RAW_BASE}/#{repo_path}/#{ref}/shard.yml")
      return YAML.parse(response.body) if response.status_code == 200
    end

    nil
  rescue ex : Exception
    Log.error { "Failed to fetch shard.yml from GitHub: #{ex.message}" }
    nil
  end

  README_FILENAMES = %w[README.md readme.md README.markdown README]

  def fetch_readme(version : String? = nil) : String?
    repo_path = extract_repo_path
    return nil unless repo_path

    candidate_refs(version).each do |ref|
      README_FILENAMES.each do |filename|
        response = HTTP::Client.get("#{GITHUB_RAW_BASE}/#{repo_path}/#{ref}/#{filename}")
        return response.body if response.status_code == 200
      end
    end

    nil
  rescue ex : Exception
    Log.error { "Failed to fetch README from GitHub: #{ex.message}" }
    nil
  end

  def fetch_metadata : RepositoryMetadata?
    repo_path = extract_repo_path
    return nil unless repo_path

    url = "#{GITHUB_API_BASE}/repos/#{repo_path}"

    headers = HTTP::Headers{"Accept" => "application/vnd.github.v3+json"}
    if token = ENV["GITHUB_TOKEN"]?
      headers["Authorization"] = "token #{token}"
    end

    response = HTTP::Client.get(url, headers: headers)
    return nil unless response.status_code == 200

    data = JSON.parse(response.body)

    RepositoryMetadata.new(
      stars: data["stargazers_count"]?.try(&.as_i?),
      forks: data["forks_count"]?.try(&.as_i?),
      description: data["description"]?.try(&.as_s?),
      homepage: data["homepage"]?.try(&.as_s?),
      default_branch: data["default_branch"]?.try(&.as_s?),
      latest_commit_sha: nil
    )
  rescue ex : Exception
    Log.error { "Failed to fetch GitHub metadata: #{ex.message}" }
    nil
  end

  def clone_repository(target_dir : String) : Bool
    cmd = "git clone --depth 1 #{repository_url} #{target_dir}"
    output = `#{cmd} 2>&1`

    $?.success?
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    cmd = "cd #{repo_dir} && git fetch --depth 1 origin tag #{version} && git checkout #{version}"
    output = `#{cmd} 2>&1`

    if $?.success?
      true
    else
      cmd = "cd #{repo_dir} && git fetch --depth 1 origin #{version} && git checkout #{version}"
      output = `#{cmd} 2>&1`
      $?.success?
    end
  end

  def extract_repo_path : String?
    if match = repository_url.match(/github\.com[\/:]([^\/]+\/[^\/\.]+)/)
      match[1].sub(/\.git$/, "")
    end
  end

  def supports_api? : Bool
    true
  end
end
