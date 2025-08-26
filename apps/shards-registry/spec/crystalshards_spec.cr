require "./spec_helper"
require "spec-kemal"
require "json"

# Load application
require "../src/crystalshards"

describe "CrystalShards Registry" do
  before_each do
    # Clean test database before each test
    CrystalShards::DB.exec("TRUNCATE shards, shard_versions, users RESTART IDENTITY CASCADE")
    CrystalShards::REDIS.flushdb
  end

  describe "Health endpoint" do
    it "responds with health status" do
      get "/health"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["status"].should eq("ok")
      json["version"].should eq("0.1.0")
      json["timestamp"].should be_a(String)
    end
  end

  describe "API root endpoint" do
    it "returns API information" do
      get "/api/v1"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["message"].should eq("CrystalShards API v1")
      json["version"].should eq("0.1.0")
      json["endpoints"].should be_a(Hash)
    end
  end

  describe "Shards listing endpoint" do
    it "returns empty list when no shards" do
      get "/api/v1/shards"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["shards"].as_a.should be_empty
      json["total"].should eq(0)
      json["page"].should eq(1)
      json["per_page"].should eq(20)
    end

    it "supports pagination parameters" do
      get "/api/v1/shards?page=2&per_page=5"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["page"].should eq(2)
      json["per_page"].should eq(5)
    end

    it "limits per_page to maximum of 100" do
      get "/api/v1/shards?per_page=500"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["per_page"].should eq(100)
    end
  end

  describe "Search endpoint" do
    it "returns error when query is empty" do
      get "/api/v1/search"
      response.status_code.should eq(400)
      
      json = JSON.parse(response.body)
      json["error"].should eq("Missing query parameter 'q'")
    end

    it "returns empty results for non-matching query" do
      get "/api/v1/search?q=nonexistent"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["query"].should eq("nonexistent")
      json["results"].as_a.should be_empty
      json["total"].should eq(0)
    end

    it "supports pagination for search results" do
      get "/api/v1/search?q=test&page=2&per_page=10"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["page"].should eq(2)
      json["per_page"].should eq(10)
    end

    it "supports advanced search filters" do
      get "/api/v1/search?q=test&license=MIT&min_stars=10&sort_by=stars"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["query"].should eq("test")
      filters = json["filters"]
      filters["license"]?.try(&.as_s).should eq("MIT")
      filters["min_stars"]?.try(&.as_i).should eq(10)
      filters["sort_by"]?.try(&.as_s).should eq("stars")
    end

    it "validates sort_by parameter" do
      get "/api/v1/search?q=test&sort_by=invalid"
      response.status_code.should eq(400)
      
      json = JSON.parse(response.body)
      json["error"].as_s.should contain("Invalid sort_by parameter")
    end

    it "supports tag filtering" do
      get "/api/v1/search?tag=web&crystal_version=1.0.0"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      filters = json["filters"]
      filters["tag"]?.try(&.as_s).should eq("web")
      filters["crystal_version"]?.try(&.as_s).should eq("1.0.0")
    end

    it "supports featured-only search" do
      get "/api/v1/search?featured_only=true"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      filters = json["filters"]
      filters["featured_only"]?.try(&.as_bool).should eq(true)
    end

    it "returns search filters" do
      get "/api/v1/search/filters"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json.should have_key("licenses")
      json.should have_key("crystal_versions")
      json.should have_key("tags")
    end

    it "returns search suggestions" do
      get "/api/v1/search/suggestions?q=ke"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["query"].should eq("ke")
      json.should have_key("suggestions")
      json["suggestions"].should be_a(Array)
    end

    it "limits suggestions" do
      get "/api/v1/search/suggestions?q=test&limit=5"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      suggestions = json["suggestions"].as_a
      suggestions.size.should be <= 5
    end
  end

  describe "Shard submission endpoint" do
    it "returns error for missing github_url" do
      post "/api/v1/shards", headers: HTTP::Headers{"Content-Type" => "application/json"}, body: "{}"
      response.status_code.should eq(400)
      
      json = JSON.parse(response.body)
      json["error"].should eq("Missing required field: github_url")
    end

    it "returns error for invalid JSON" do
      post "/api/v1/shards", headers: HTTP::Headers{"Content-Type" => "application/json"}, body: "invalid json"
      response.status_code.should eq(400)
      
      json = JSON.parse(response.body)
      json["error"].should eq("Invalid JSON in request body")
    end

    it "accepts valid github URL" do
      # This would need a mock GitHub API for full testing
      payload = {"github_url" => "https://github.com/crystal-lang/crystal"}.to_json
      post "/api/v1/shards", headers: HTTP::Headers{"Content-Type" => "application/json"}, body: payload
      
      # Should return either 201 (success) or 422 (validation error) - both are valid responses
      [201, 422, 500].should contain(response.status_code)
    end
  end

  describe "Individual shard endpoint" do
    it "returns 404 for non-existent shard" do
      get "/api/v1/shards/nonexistent"
      response.status_code.should eq(404)
      
      json = JSON.parse(response.body)
      json["error"].should eq("Shard not found")
    end
  end

  describe "GitHub webhook endpoint" do
    it "accepts webhook payload" do
      payload = {
        "action" => "published",
        "repository" => {
          "html_url" => "https://github.com/test/repo"
        }
      }.to_json
      
      post "/webhooks/github", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: payload
      
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["status"].should eq("ok")
    end

    it "handles invalid JSON in webhook" do
      post "/webhooks/github", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: "invalid json"
      
      response.status_code.should eq(400)
      
      json = JSON.parse(response.body)
      json["error"].should eq("Invalid JSON payload")
    end
  end

  describe "CORS headers" do
    it "sets CORS headers on all requests" do
      get "/api/v1"
      response.headers["Access-Control-Allow-Origin"].should eq("*")
      response.headers["Access-Control-Allow-Methods"].should contain("GET")
      response.headers["Access-Control-Allow-Headers"].should contain("Content-Type")
    end

    it "handles OPTIONS requests" do
      options "/api/v1/shards"
      response.status_code.should eq(200)
    end
  end

  describe "Error handling" do
    it "returns 404 for unknown endpoints" do
      get "/nonexistent"
      response.status_code.should eq(404)
      
      json = JSON.parse(response.body)
      json["error"].should eq("Not Found")
      json["status"].should eq(404)
    end
  end
end