require "http/client"
require "json"
require "yaml"
require "db"
require "../models"
require "../repositories/shard_repository"

module CrystalShards
  class ShardSubmissionService
    def initialize(@db : DB::Database, @redis : Redis::Client)
      @shard_repo = ShardRepository.new(@db)
    end
    
    def submit_from_github(github_url : String) : {shard: CrystalShared::Shard?, errors: Array(String)}
      errors = [] of String
      
      # Validate GitHub URL format
      unless valid_github_url?(github_url)
        errors << "Invalid GitHub URL format"
        return {shard: nil, errors: errors}
      end
      
      # Extract owner and repo name
      owner, repo = extract_owner_repo(github_url)
      if owner.empty? || repo.empty?
        errors << "Could not extract owner/repo from GitHub URL"
        return {shard: nil, errors: errors}
      end
      
      # Check if shard already exists
      if existing = @shard_repo.find_by_github_url(github_url)
        errors << "Shard already exists with ID #{existing.id}"
        return {shard: existing, errors: errors}
      end
      
      # Fetch GitHub repository information
      github_info = fetch_github_info(owner, repo)
      unless github_info
        errors << "Could not fetch repository information from GitHub"
        return {shard: nil, errors: errors}
      end
      
      # Fetch shard.yml to get shard configuration
      shard_yml = fetch_shard_yml(owner, repo)
      unless shard_yml
        errors << "Could not find or parse shard.yml file"
        return {shard: nil, errors: errors}
      end
      
      # Validate shard.yml has required fields
      unless shard_yml["name"]? && shard_yml["name"].as_s.strip != ""
        errors << "shard.yml missing required 'name' field"
        return {shard: nil, errors: errors}
      end
      
      # Create shard from GitHub info and shard.yml
      shard = build_shard_from_github(github_url, github_info, shard_yml)
      
      # Validate shard name doesn't conflict
      if existing_name = @shard_repo.find_by_name(shard.name)
        errors << "Shard name '#{shard.name}' is already taken"
        return {shard: existing_name, errors: errors}
      end
      
      # Save shard to database
      saved_shard = @shard_repo.create(shard)
      unless saved_shard
        errors << "Failed to save shard to database"
        return {shard: nil, errors: errors}
      end
      
      # Cache the submission to prevent spam
      cache_key = "submitted:#{github_url}"
      @redis.setex(cache_key, 3600, Time.utc.to_s) # 1 hour cache
      
      {shard: saved_shard, errors: errors}
    rescue ex : Exception
      errors << "Internal error: #{ex.message}"
      {shard: nil, errors: errors}
    end
    
    def update_github_stats(shard_id : Int32) : Bool
      shard = @shard_repo.find_by_id(shard_id)
      return false unless shard
      
      owner, repo = shard.github_owner_repo
      return false if owner.empty? || repo.empty?
      
      github_info = fetch_github_info(owner, repo)
      return false unless github_info
      
      stars = github_info["stargazers_count"].as_i
      forks = github_info["forks_count"].as_i
      last_activity = Time.parse_iso8601(github_info["updated_at"].as_s)
      
      @shard_repo.update_github_stats(shard_id, stars, forks, last_activity)
    rescue
      false
    end
    
    def recently_submitted?(github_url : String) : Bool
      cache_key = "submitted:#{github_url}"
      @redis.exists(cache_key) == 1
    end
    
    private def valid_github_url?(url : String) : Bool
      url.match(/^https:\/\/github\.com\/[^\/]+\/[^\/]+\/?$/)
    end
    
    private def extract_owner_repo(github_url : String) : {String, String}
      if match = github_url.match(/github\.com\/([^\/]+)\/([^\/]+)/)
        owner = match[1]
        repo = match[2].gsub(/\.git$/, "") # Remove .git suffix if present
        {owner, repo}
      else
        {"", ""}
      end
    end
    
    private def fetch_github_info(owner : String, repo : String) : JSON::Any?
      github_token = ENV["GITHUB_TOKEN"]?
      headers = HTTP::Headers.new
      headers["User-Agent"] = "CrystalShards/1.0"
      headers["Authorization"] = "token #{github_token}" if github_token
      
      response = HTTP::Client.get("https://api.github.com/repos/#{owner}/#{repo}", headers: headers)
      
      if response.status_code == 200
        JSON.parse(response.body)
      else
        nil
      end
    rescue
      nil
    end
    
    private def fetch_shard_yml(owner : String, repo : String) : YAML::Any?
      github_token = ENV["GITHUB_TOKEN"]?
      headers = HTTP::Headers.new
      headers["User-Agent"] = "CrystalShards/1.0"
      headers["Authorization"] = "token #{github_token}" if github_token
      
      response = HTTP::Client.get("https://api.github.com/repos/#{owner}/#{repo}/contents/shard.yml", headers: headers)
      
      if response.status_code == 200
        content_info = JSON.parse(response.body)
        if content_info["encoding"]?.try(&.as_s) == "base64"
          decoded = Base64.decode_string(content_info["content"].as_s.gsub(/\s/, ""))
          YAML.parse(decoded)
        end
      else
        nil
      end
    rescue
      nil
    end
    
    private def build_shard_from_github(github_url : String, github_info : JSON::Any, shard_yml : YAML::Any) : CrystalShared::Shard
      name = shard_yml["name"].as_s
      shard = CrystalShared::Shard.new(name, github_url)
      
      # From shard.yml
      shard.description = shard_yml["description"]?.try(&.as_s)
      shard.license = shard_yml["license"]?.try(&.as_s)
      shard.homepage_url = shard_yml["homepage"]?.try(&.as_s)
      
      # Extract version from shard.yml
      if version = shard_yml["version"]?.try(&.as_s)
        shard.latest_version = version
      end
      
      # Extract Crystal version compatibility
      if crystal = shard_yml["crystal"]?.try(&.as_s)
        shard.crystal_versions = [crystal]
      end
      
      # Extract dependencies
      if deps = shard_yml["dependencies"]?.try(&.as_h)
        dependencies = {} of String => String
        deps.each do |dep_name, dep_info|
          if dep_info.as_h?
            if github_dep = dep_info["github"]?.try(&.as_s)
              dependencies[dep_name.as_s] = "github:#{github_dep}"
            elsif version_dep = dep_info["version"]?.try(&.as_s)
              dependencies[dep_name.as_s] = "version:#{version_dep}"
            end
          end
        end
        shard.dependencies = dependencies
      end
      
      # From GitHub API
      shard.description = github_info["description"]?.try(&.as_s) if shard.description.nil?
      shard.stars = github_info["stargazers_count"].as_i
      shard.forks = github_info["forks_count"].as_i
      shard.last_activity = Time.parse_iso8601(github_info["updated_at"].as_s)
      
      # Extract homepage from GitHub if not in shard.yml
      if shard.homepage_url.nil?
        if homepage = github_info["homepage"]?.try(&.as_s)
          shard.homepage_url = homepage unless homepage.empty?
        end
      end
      
      # Extract topics as tags
      if topics = github_info["topics"]?.try(&.as_a)
        shard.tags = topics.map(&.as_s)
      end
      
      # Set as unpublished initially (requires manual approval)
      shard.published = false
      
      shard
    end
  end
end