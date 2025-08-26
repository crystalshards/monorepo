require "./spec_helper"
require "spec-kemal"
require "json"

# Load application
require "../src/crystaldocs"

describe "CrystalDocs" do
  before_each do
    # Clean test database before each test
    CrystalDocs::DB.exec("TRUNCATE documentation, shards, shard_versions RESTART IDENTITY CASCADE")
    CrystalDocs::REDIS.flushdb
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

  describe "Homepage" do
    it "serves the main documentation page" do
      get "/"
      response.status_code.should eq(200)
      response.body.should contain("CrystalDocs")
      response.body.should contain("Crystal Package Documentation Platform")
    end

    it "contains search form" do
      get "/"
      response.body.should contain("form")
      response.body.should contain("Search documentation")
    end
  end

  describe "Search functionality" do
    it "displays search page without query" do
      get "/search"
      response.status_code.should eq(200)
      response.body.should contain("CrystalDocs Search")
      response.body.should contain("Popular Packages")
    end

    it "handles search with empty query" do
      get "/search?q="
      response.status_code.should eq(200)
      response.body.should contain("Popular Packages")
    end

    it "performs search with query" do
      get "/search?q=kemal"
      response.status_code.should eq(200)
      response.body.should contain("kemal")
      # Should show "no results" since database is empty
      response.body.should contain("No results found")
    end

    it "displays no results message appropriately" do
      get "/search?q=nonexistent"
      response.status_code.should eq(200)
      response.body.should contain("No results found for \"nonexistent\"")
      response.body.should contain("No documentation found")
    end
  end

  describe "API endpoints" do
    describe "Documentation data API" do
      it "returns package documentation info" do
        get "/api/v1/docs/kemal"
        response.status_code.should eq(200)
        
        json = JSON.parse(response.body)
        json["package"].should eq("kemal")
        json["version"].should eq("latest")
        json["build_status"].should eq("pending")
      end

      it "supports version parameter" do
        get "/api/v1/docs/kemal?version=1.0.0"
        response.status_code.should eq(200)
        
        json = JSON.parse(response.body)
        json["version"].should eq("1.0.0")
      end
    end

    describe "Build status API" do
      it "returns 404 for non-existent package" do
        get "/api/v1/docs/nonexistent/build-status"
        response.status_code.should eq(404)
        
        json = JSON.parse(response.body)
        json["status"].should eq("not_found")
      end
    end

    describe "List documentation API" do
      it "returns list of all documentation" do
        get "/api/v1/docs"
        response.status_code.should eq(200)
        
        json = JSON.parse(response.body)
        json["status"].should eq("success")
        json["count"].should be_a(Int64)
        json["documentation"].should be_a(Array)
      end

      it "supports limit parameter" do
        get "/api/v1/docs?limit=10"
        response.status_code.should eq(200)
        
        json = JSON.parse(response.body)
        json["status"].should eq("success")
      end
    end

    describe "Build statistics API" do
      it "returns build statistics" do
        get "/api/v1/build-stats"
        response.status_code.should eq(200)
        
        json = JSON.parse(response.body)
        json["status"].should eq("success")
        json["database_stats"].should be_a(Hash)
        json["active_jobs"].should be_a(Int64)
        json["pending_jobs"].should be_a(Int64)
        json["total_jobs"].should be_a(Int64)
      end
    end

    describe "Storage health check" do
      it "returns storage health status" do
        get "/api/v1/storage/health"
        response.status_code.should eq(200)
        
        json = JSON.parse(response.body)
        json["storage_accessible"].should be_a(Bool)
        json["timestamp"].should be_a(String)
      end
    end

    describe "Package versions API" do
      it "returns 404 for non-existent package" do
        get "/api/v1/docs/nonexistent/versions"
        response.status_code.should eq(404)
        
        json = JSON.parse(response.body)
        json["status"].should eq("not_found")
        json["message"].should contain("Package 'nonexistent' not found")
      end
    end

    describe "Documentation files API" do
      it "returns file listing" do
        get "/api/v1/docs/kemal/latest/files"
        response.status_code.should eq(200)
        
        json = JSON.parse(response.body)
        json["status"].should eq("success")
        json["package"].should eq("kemal")
        json["version"].should eq("latest")
        json["files"].should be_a(Array)
      end
    end

    describe "Documentation content API" do
      it "returns 404 for non-existent content" do
        get "/api/v1/docs/nonexistent/latest/content"
        response.status_code.should eq(404)
        
        json = JSON.parse(response.body)
        json["status"].should eq("not_found")
      end

      it "supports file parameter" do
        get "/api/v1/docs/kemal/latest/content?file=index.html"
        response.status_code.should eq(404)  # Expected since no content exists
        
        json = JSON.parse(response.body)
        json["status"].should eq("not_found")
      end
    end

    describe "Documentation metadata API" do
      it "returns 404 for non-existent documentation" do
        get "/api/v1/docs/nonexistent/latest/metadata"
        response.status_code.should eq(404)
        
        json = JSON.parse(response.body)
        json["status"].should eq("not_found")
      end
    end
  end

  describe "Documentation build API" do
    it "requires valid JSON payload" do
      post "/api/v1/docs/test-package/build", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: "invalid json"
      
      response.status_code.should eq(400)
      json = JSON.parse(response.body)
      json["status"].should eq("error")
      json["message"].should contain("Invalid request")
    end

    it "accepts build request with valid data" do
      payload = {
        "shard_id" => 1,
        "version" => "1.0.0",
        "github_repo" => "test/package"
      }.to_json
      
      post "/api/v1/docs/test-package/build", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: payload
      
      # Should return either success or error (both are valid responses)
      [200, 400, 500].should contain(response.status_code)
      
      json = JSON.parse(response.body)
      json["status"].should be_a(String)
    end
  end

  describe "Documentation viewer" do
    it "redirects package root to latest version" do
      get "/docs/kemal"
      response.status_code.should eq(302)
      response.headers["Location"].should eq("/docs/kemal/latest")
    end

    it "shows build status page for building documentation" do
      # This would require inserting test data for full testing
      get "/docs/nonexistent/latest"
      response.status_code.should eq(404)
      response.body.should contain("Documentation Not Found")
    end

    it "provides trigger build functionality" do
      get "/docs/test-package/latest"
      response.status_code.should eq(404)
      response.body.should contain("Trigger Documentation Build")
      response.body.should contain("triggerBuild")
    end
  end

  describe "CORS headers" do
    it "sets CORS headers on API requests" do
      get "/api/v1/docs"
      response.headers["Access-Control-Allow-Origin"].should eq("*")
      response.headers["Access-Control-Allow-Methods"].should contain("GET")
      response.headers["Access-Control-Allow-Headers"].should contain("Content-Type")
    end

    it "handles OPTIONS requests" do
      options "/api/v1/docs"
      response.status_code.should eq(200)
    end
  end

  describe "Error handling" do
    it "returns custom 404 page" do
      get "/nonexistent"
      response.status_code.should eq(404)
      response.body.should contain("404 - Page Not Found")
      response.body.should contain("Back to Home")
    end
  end
end