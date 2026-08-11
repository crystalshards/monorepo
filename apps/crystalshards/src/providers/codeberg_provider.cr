require "./base_provider"
require "http/client"
require "json"

class CodebergProvider < BaseProvider
  CODEBERG_API_BASE = "https://codeberg.org/api/v1"

  def fetch_shard_yml(version : String? = nil) : YAML::Any?
    repo_path = extract_repo_path
    return nil unless repo_path

    ref = version || "main"
    url = "#{CODEBERG_API_BASE}/repos/#{repo_path}/raw/#{ref}/shard.yml"

    headers = HTTP::Headers{"Accept" => "application/json"}
    if token = ENV["CODEBERG_TOKEN"]?
      headers["Authorization"] = "token #{token}"
    end

    response = HTTP::Client.get(url, headers: headers)
    return nil unless response.status_code == 200

    YAML.parse(response.body)
  rescue ex : Exception
    Log.error { "Failed to fetch shard.yml from Codeberg: #{ex.message}" }
    nil
  end

  def fetch_metadata : RepositoryMetadata?
    repo_path = extract_repo_path
    return nil unless repo_path

    url = "#{CODEBERG_API_BASE}/repos/#{repo_path}"

    headers = HTTP::Headers{"Accept" => "application/json"}
    if token = ENV["CODEBERG_TOKEN"]?
      headers["Authorization"] = "token #{token}"
    end

    response = HTTP::Client.get(url, headers: headers)
    return nil unless response.status_code == 200

    data = JSON.parse(response.body)

    RepositoryMetadata.new(
      stars: data["stars_count"]?.try(&.as_i?),
      forks: data["forks_count"]?.try(&.as_i?),
      description: data["description"]?.try(&.as_s?),
      homepage: data["website"]?.try(&.as_s?),
      default_branch: data["default_branch"]?.try(&.as_s?),
      latest_commit_sha: nil
    )
  rescue ex : Exception
    Log.error { "Failed to fetch Codeberg metadata: #{ex.message}" }
    nil
  end

  def clone_repository(target_dir : String) : Bool
    clone_git_repository(target_dir)
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    checkout_git_version(repo_dir, version)
  end

  def extract_repo_path : String?
    if match = repository_url.match(/codeberg\.org[\/:]([^\/]+\/[^\/\.]+)/)
      match[1].sub(/\.git$/, "")
    end
  end

  def supports_api? : Bool
    true
  end
end
