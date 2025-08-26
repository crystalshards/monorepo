require "http/client"
require "json"
require "uri"

# CrystalShards API Client Example
# 
# This example demonstrates how to interact with the CrystalShards Platform API
# using Crystal's built-in HTTP client.

module CrystalShardsClient
  VERSION = "1.0.0"
  
  class Client
    getter base_url : String
    getter api_key : String?
    
    def initialize(@base_url = "https://api.crystalshards.org", @api_key = nil)
    end
    
    # Create HTTP client with proper headers
    private def http_client
      client = HTTP::Client.new(URI.parse(@base_url))
      client.before_request do |request|
        request.headers["Content-Type"] = "application/json"
        request.headers["User-Agent"] = "CrystalShardsClient/#{VERSION}"
        
        if api_key = @api_key
          request.headers["Authorization"] = "Bearer #{api_key}"
        end
      end
      client
    end
    
    # Search for shards
    def search_shards(query : String, **options)
      params = URI::Params.build do |form|
        form.add("q", query)
        
        options.each do |key, value|
          next if value.nil?
          form.add(key.to_s, value.to_s)
        end
      end
      
      response = http_client.get("/api/v1/search?#{params}")
      
      if response.success?
        JSON.parse(response.body)
      else
        raise "Search failed: #{response.status_code} - #{response.body}"
      end
    end
    
    # Get shard details
    def get_shard(name : String)
      response = http_client.get("/api/v1/shards/#{name}")
      
      if response.success?
        JSON.parse(response.body)
      elsif response.status_code == 404
        nil
      else
        raise "Failed to get shard: #{response.status_code} - #{response.body}"
      end
    end
    
    # Submit a new shard (requires authentication)
    def submit_shard(github_url : String)
      unless @api_key
        raise "API key required for shard submission"
      end
      
      payload = {
        github_url: github_url
      }.to_json
      
      response = http_client.post("/api/v1/shards", body: payload)
      
      case response.status_code
      when 201
        JSON.parse(response.body)
      when 409
        result = JSON.parse(response.body)
        puts "Shard already exists: #{result["shard"]?}"
        result
      when 401
        raise "Unauthorized: Invalid or missing API key"
      when 403
        raise "Forbidden: Insufficient permissions (shards:write scope required)"
      when 422
        result = JSON.parse(response.body)
        raise "Submission failed: #{result["errors"]?}"
      when 429
        raise "Rate limited: Shard recently submitted"
      else
        raise "Submission failed: #{response.status_code} - #{response.body}"
      end
    end
    
    # Get search suggestions
    def get_suggestions(query : String, limit = 10)
      params = URI::Params.build do |form|
        form.add("q", query)
        form.add("limit", limit.to_s)
      end
      
      response = http_client.get("/api/v1/search/suggestions?#{params}")
      
      if response.success?
        JSON.parse(response.body)
      else
        raise "Failed to get suggestions: #{response.status_code} - #{response.body}"
      end
    end
    
    # Get trending searches
    def get_trending_searches(limit = 20)
      params = URI::Params.build do |form|
        form.add("limit", limit.to_s)
      end
      
      response = http_client.get("/api/v1/search/trending?#{params}")
      
      if response.success?
        JSON.parse(response.body)
      else
        raise "Failed to get trending searches: #{response.status_code} - #{response.body}"
      end
    end
    
    # Get API info
    def get_api_info
      response = http_client.get("/api/v1")
      
      if response.success?
        JSON.parse(response.body)
      else
        raise "Failed to get API info: #{response.status_code} - #{response.body}"
      end
    end
    
    # Get service health
    def health_check
      response = http_client.get("/health")
      
      if response.success?
        JSON.parse(response.body)
      else
        raise "Health check failed: #{response.status_code} - #{response.body}"
      end
    end
  end
end

# Example usage
if ARGV.includes?("--example")
  # Create client instance
  client = CrystalShardsClient::Client.new
  
  # Get API information
  puts "=== API Info ==="
  api_info = client.get_api_info
  puts "API: #{api_info["message"]?}"
  puts "Version: #{api_info["version"]?}"
  puts
  
  # Health check
  puts "=== Health Check ==="
  health = client.health_check
  puts "Status: #{health["status"]?}"
  puts "Timestamp: #{health["timestamp"]?}"
  puts
  
  # Search for shards
  puts "=== Search Results ==="
  results = client.search_shards(
    query: "web framework",
    sort_by: "stars",
    per_page: 5,
    highlight: true
  )
  
  puts "Query: #{results["query"]?}"
  puts "Total: #{results["total"]?}"
  puts "Results:"
  
  if results["results"]?
    results["results"].as_a.each_with_index do |shard, index|
      puts "  #{index + 1}. #{shard["name"]?} - #{shard["description"]?}"
      puts "     ⭐ #{shard["stars"]?} stars | 📦 #{shard["downloads"]?} downloads"
    end
  end
  puts
  
  # Get specific shard
  puts "=== Shard Details ==="
  if shard = client.get_shard("kemal")
    puts "Name: #{shard["name"]?}"
    puts "Description: #{shard["description"]?}"
    puts "GitHub: #{shard["github_url"]?}"
    puts "License: #{shard["license"]?}"
    puts "Stars: #{shard["stars"]?}"
    puts "Tags: #{shard["tags"]?.try(&.as_a.join(", "))}"
  else
    puts "Shard 'kemal' not found"
  end
  puts
  
  # Get suggestions
  puts "=== Search Suggestions ==="
  suggestions = client.get_suggestions("kem", 5)
  puts "Suggestions for 'kem':"
  if suggestions["suggestions"]?
    suggestions["suggestions"].as_a.each do |suggestion|
      puts "  - #{suggestion}"
    end
  end
  puts
  
  # Get trending searches
  puts "=== Trending Searches ==="
  trending = client.get_trending_searches(5)
  puts "Trending searches (#{trending["period"]?}):"
  if trending["trending_searches"]?
    trending["trending_searches"].as_a.each_with_index do |search, index|
      query = search["query"]?
      count = search["count"]?
      growth_rate = search["growth_rate"]?
      puts "  #{index + 1}. \"#{query}\" - #{count} searches (#{growth_rate}% growth)"
    end
  end
  
  puts "\n✨ Example completed successfully!"
  puts "\n💡 To submit a shard, set your API key:"
  puts "   export CRYSTALSHARDS_API_KEY=\"your-api-key\""
  puts "   client = CrystalShardsClient::Client.new(api_key: ENV[\"CRYSTALSHARDS_API_KEY\"]?)"
  puts "   client.submit_shard(\"https://github.com/user/repo\")"
end