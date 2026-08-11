require "./base_provider"
require "http/client"
require "json"

class BitbucketProvider < BaseProvider
  BITBUCKET_API_BASE = "https://api.bitbucket.org/2.0"

  def fetch_shard_yml(version : String? = nil) : YAML::Any?
    repo_path = extract_repo_path
    return nil unless repo_path

    ref = version || "HEAD"
    url = "#{BITBUCKET_API_BASE}/repositories/#{repo_path}/src/#{ref}/shard.yml"

    headers = HTTP::Headers{"Accept" => "application/json"}
    if username = ENV["BITBUCKET_USERNAME"]?
      if password = ENV["BITBUCKET_APP_PASSWORD"]?
        credentials = Base64.strict_encode("#{username}:#{password}")
        headers["Authorization"] = "Basic #{credentials}"
      end
    end

    response = HTTP::Client.get(url, headers: headers)
    return nil unless response.status_code == 200

    YAML.parse(response.body)
  rescue ex : Exception
    Log.error { "Failed to fetch shard.yml from Bitbucket: #{ex.message}" }
    nil
  end

  def fetch_metadata : RepositoryMetadata?
    repo_path = extract_repo_path
    return nil unless repo_path

    url = "#{BITBUCKET_API_BASE}/repositories/#{repo_path}"

    headers = HTTP::Headers{"Accept" => "application/json"}
    if username = ENV["BITBUCKET_USERNAME"]?
      if password = ENV["BITBUCKET_APP_PASSWORD"]?
        credentials = Base64.strict_encode("#{username}:#{password}")
        headers["Authorization"] = "Basic #{credentials}"
      end
    end

    response = HTTP::Client.get(url, headers: headers)
    return nil unless response.status_code == 200

    data = JSON.parse(response.body)

    homepage_url = data["links"]?.try { |links| links["html"]? }.try { |html| html["href"]? }.try(&.as_s?)
    default_branch_name = data["mainbranch"]?.try { |mb| mb["name"]? }.try(&.as_s?)

    RepositoryMetadata.new(
      stars: nil,
      forks: nil,
      description: data["description"]?.try(&.as_s?),
      homepage: homepage_url,
      default_branch: default_branch_name,
      latest_commit_sha: nil
    )
  rescue ex : Exception
    Log.error { "Failed to fetch Bitbucket metadata: #{ex.message}" }
    nil
  end

  def clone_repository(target_dir : String) : Bool
    clone_git_repository(target_dir)
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    checkout_git_version(repo_dir, version)
  end

  def extract_repo_path : String?
    if match = repository_url.match(/bitbucket\.org[\/:]([^\/]+\/[^\/\.]+)/)
      match[1].sub(/\.git$/, "")
    end
  end

  def supports_api? : Bool
    true
  end
end
