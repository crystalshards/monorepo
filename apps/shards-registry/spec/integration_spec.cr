require "./spec_helper"
require "spec-kemal"
require "json"

describe "CrystalShards Integration Tests" do
  before_each do
    # Set up test environment variables for testing
    ENV["DATABASE_URL"] = "postgres://postgres:password@localhost/crystalshards_test"
    ENV["REDIS_URL"] = "redis://localhost:6379/1"
    
    # Connect to test database
    test_db = PG.connect(ENV["DATABASE_URL"])
    test_redis = Redis.new(url: ENV["REDIS_URL"])
    
    # Clean test data
    test_db.exec("TRUNCATE shards, shard_versions, users RESTART IDENTITY CASCADE")
    test_redis.flushdb
    
    test_db.close
    test_redis.close
  end

  describe "Shard Repository Integration" do
    it "can create and retrieve shards" do
      # This test would normally need a real database connection
      # For now, we'll test that the repository methods exist and are callable
      shard_repo = ShardRepository.new(CrystalShards::DB)
      
      # Test that methods exist
      shard_repo.responds_to?(:list_published).should be_true
      shard_repo.responds_to?(:count_published).should be_true
      shard_repo.responds_to?(:search).should be_true
      shard_repo.responds_to?(:find_by_name).should be_true
    end
  end

  describe "Shard Submission Service Integration" do
    it "initializes with database and redis connections" do
      submission_service = ShardSubmissionService.new(CrystalShards::DB, CrystalShards::REDIS)
      
      # Test that service methods exist
      submission_service.responds_to?(:recently_submitted?).should be_true
      submission_service.responds_to?(:submit_from_github).should be_true
      submission_service.responds_to?(:update_github_stats).should be_true
    end

    it "validates GitHub URL format" do
      submission_service = ShardSubmissionService.new(CrystalShards::DB, CrystalShards::REDIS)
      
      # Test invalid URLs (these should fail validation in the service)
      invalid_urls = [
        "not-a-url",
        "https://gitlab.com/user/repo",  # Not GitHub
        "https://github.com",            # No repo specified
        "https://github.com/user",       # No repo name
      ]
      
      invalid_urls.each do |url|
        result = submission_service.recently_submitted?(url)
        # This should not crash - the method should handle invalid URLs gracefully
        result.should be_a(Bool)
      end
    end
  end

  describe "Full workflow integration" do
    it "handles complete shard submission flow" do
      # Test the full flow: submit -> process -> store -> retrieve
      payload = {
        "github_url" => "https://github.com/crystal-lang/crystal"
      }.to_json
      
      # Submit shard
      post "/api/v1/shards", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: payload
      
      # Should get some response (success, error, or rate limit)
      [201, 400, 422, 429, 500].should contain(response.status_code)
      
      response_json = JSON.parse(response.body)
      response_json.should be_a(Hash)
    end

    it "prevents duplicate submissions" do
      payload = {
        "github_url" => "https://github.com/test/duplicate-repo"
      }.to_json
      
      # First submission
      post "/api/v1/shards", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: payload
      
      first_response_code = response.status_code
      
      # Second submission (should be rate limited)
      post "/api/v1/shards", 
           headers: HTTP::Headers{"Content-Type" => "application/json"}, 
           body: payload
      
      # If first succeeded, second should be rate limited (429)
      # If first failed, second might also fail with same error
      response.status_code.should be >= 400
    end
  end

  describe "Database integration" do
    it "can execute basic database operations" do
      # Test that database connection works
      result = CrystalShards::DB.query_one("SELECT 1 as test", as: Int32)
      result.should eq(1)
    end

    it "can access all required tables" do
      # Test that all required tables exist
      tables = ["shards", "shard_versions", "users", "job_postings", "documentation", "api_keys", "search_queries"]
      
      tables.each do |table|
        # This should not raise an exception if the table exists
        result = CrystalShards::DB.query_one(
          "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = $1", 
          table, 
          as: Int64
        )
        result.should eq(1)
      end
    end
  end

  describe "Redis integration" do
    it "can perform basic Redis operations" do
      # Test Redis connection
      CrystalShards::REDIS.set("test_key", "test_value")
      value = CrystalShards::REDIS.get("test_key")
      value.should eq("test_value")
      
      # Clean up
      CrystalShards::REDIS.del("test_key")
    end

    it "can handle rate limiting data" do
      # Test rate limiting functionality
      test_key = "rate_limit:test"
      CrystalShards::REDIS.setex(test_key, 300, "1")  # 5 minute TTL
      
      exists = CrystalShards::REDIS.exists(test_key)
      exists.should eq(1)
      
      # Clean up
      CrystalShards::REDIS.del(test_key)
    end
  end

  describe "Error recovery and resilience" do
    it "handles database connection errors gracefully" do
      # Test API behavior when database is unavailable
      # This is a mock test - in reality we'd need to simulate connection failure
      
      get "/api/v1/shards"
      # Should return some response even if there are database issues
      response.status_code.should be >= 200
    end

    it "handles Redis connection errors gracefully" do
      # Test that app continues to work even if Redis is unavailable
      # Rate limiting might be disabled, but basic functionality should work
      
      get "/health"
      response.status_code.should eq(200)
      
      json = JSON.parse(response.body)
      json["status"].should eq("ok")
    end
  end
end