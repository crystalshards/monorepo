require "./base_provider"
require "http/client"
require "json"
require "uri"

class GitlabProvider < BaseProvider
  GITLAB_API_BASE = "https://gitlab.com/api/v4"

  def fetch_shard_yml(version : String? = nil) : YAML::Any?
    repo_path = extract_repo_path
    return nil unless repo_path

    encoded_path = URI.encode_path_segment(repo_path)
    ref = version || "HEAD"
    url = "#{GITLAB_API_BASE}/projects/#{encoded_path}/repository/files/shard.yml/raw?ref=#{ref}"

    headers = HTTP::Headers{"Accept" => "application/json"}
    if token = ENV["GITLAB_TOKEN"]?
      headers["PRIVATE-TOKEN"] = token
    end

    response = HTTP::Client.get(url, headers: headers)
    return nil unless response.status_code == 200

    YAML.parse(response.body)
  rescue ex : Exception
    Log.error { "Failed to fetch shard.yml from GitLab: #{ex.message}" }
    nil
  end

  def fetch_metadata : RepositoryMetadata?
    repo_path = extract_repo_path
    return nil unless repo_path

    encoded_path = URI.encode_path_segment(repo_path)
    url = "#{GITLAB_API_BASE}/projects/#{encoded_path}"

    headers = HTTP::Headers{"Accept" => "application/json"}
    if token = ENV["GITLAB_TOKEN"]?
      headers["PRIVATE-TOKEN"] = token
    end

    response = HTTP::Client.get(url, headers: headers)
    return nil unless response.status_code == 200

    data = JSON.parse(response.body)

    RepositoryMetadata.new(
      stars: data["star_count"]?.try(&.as_i?),
      forks: data["forks_count"]?.try(&.as_i?),
      description: data["description"]?.try(&.as_s?),
      homepage: data["web_url"]?.try(&.as_s?),
      default_branch: data["default_branch"]?.try(&.as_s?),
      latest_commit_sha: nil
    )
  rescue ex : Exception
    Log.error { "Failed to fetch GitLab metadata: #{ex.message}" }
    nil
  end

  def clone_repository(target_dir : String) : Bool
    clone_git_repository(target_dir)
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    checkout_git_version(repo_dir, version)
  end

  def extract_repo_path : String?
    if match = repository_url.match(/gitlab\.com[\/:]([^\/]+\/[^\/\.]+)/)
      match[1].sub(/\.git$/, "")
    end
  end

  def supports_api? : Bool
    true
  end
end
