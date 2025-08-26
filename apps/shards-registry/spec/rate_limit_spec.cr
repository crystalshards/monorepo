require "./spec_helper"
require "../src/middleware/rate_limit_middleware"
require "../src/controllers/analytics_controller"

describe "Rate Limiting" do
  let(:redis) { Redis.new(url: "redis://localhost:6379/15") } # Use test database
  let(:middleware) { CrystalShards::RateLimitMiddleware.new(redis) }
  let(:analytics_service) { CrystalShards::UsageAnalyticsService.new(redis) }
  
  before_each do
    # Clean test database
    redis.flushdb
  end
  
  after_all do
    redis.close
  end
  
  describe "RateLimitMiddleware" do
    it "allows requests under the limit" do
      # Create a test request context
      request = HTTP::Request.new("GET", "/api/v1/shards")
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(request, response)
      
      # Simulate Kemal environment
      env = Kemal::Context.new(request, response)
      
      # Should allow first request
      middleware.call(env)
      
      # Check rate limit headers are set
      env.response.headers["X-RateLimit-Limit"].should eq("100")
      env.response.headers["X-RateLimit-Remaining"].should eq("99")
    end
    
    it "blocks requests over the limit" do
      request = HTTP::Request.new("GET", "/api/v1/shards")
      response = HTTP::Server::Response.new(IO::Memory.new)
      env = Kemal::Context.new(request, response)
      
      # Simulate exceeding anonymous limit (100 requests)
      ip = "127.0.0.1"
      rate_key = "anon:#{ip}"
      
      # Add 100 requests to exceed limit
      (1..101).each do |i|
        redis.zadd(rate_key, Time.utc.to_unix, "request-#{i}")
      end
      
      # This request should be blocked
      result = middleware.call(env)
      
      response.status_code.should eq(429)
      response.headers["Retry-After"].should be_truthy
    end
    
    it "has different limits for authenticated vs anonymous users" do
      # Test anonymous limit
      anon_limits = CrystalShards::RateLimitMiddleware::LIMITS["anonymous"]
      anon_limits[:requests].should eq(100)
      
      # Test authenticated JWT limit
      jwt_limits = CrystalShards::RateLimitMiddleware::LIMITS["jwt_authenticated"]
      jwt_limits[:requests].should eq(2000)
      
      # Test API key limits
      api_admin_limits = CrystalShards::RateLimitMiddleware::LIMITS["api_key_admin"]
      api_admin_limits[:requests].should eq(10000)
    end
  end
  
  describe "UsageAnalyticsService" do
    it "records and retrieves usage statistics" do
      # Record some test analytics data
      today = Date.utc
      analytics_key = "analytics:#{today.to_s("%Y-%m-%d")}"
      
      test_requests = [
        {
          timestamp: Time.utc.to_unix,
          path: "/api/v1/shards",
          method: "GET",
          rate_key: "anon:127.0.0.1",
          user_agent: "test-agent",
          authenticated: false
        },
        {
          timestamp: Time.utc.to_unix,
          path: "/api/v1/search",
          method: "GET", 
          rate_key: "jwt:123",
          user_agent: "test-agent",
          authenticated: true
        }
      ]
      
      test_requests.each do |request|
        redis.lpush(analytics_key, request.to_json)
      end
      
      # Test retrieving stats
      stats = analytics_service.get_usage_stats(today, today)
      
      stats.should have_key(today.to_s)
      daily_stats = stats[today.to_s]
      
      daily_stats["total_requests"].should eq(2)
      daily_stats["authenticated_requests"].should eq(1)
      daily_stats["anonymous_requests"].should eq(1)
    end
    
    it "gets rate limit status correctly" do
      rate_key = "jwt:123"
      limit_type = "jwt_authenticated"
      
      # Add some requests
      current_time = Time.utc.to_unix
      redis.zadd(rate_key, current_time, "request-1")
      redis.zadd(rate_key, current_time - 10, "request-2")
      
      status = analytics_service.get_rate_limit_status(rate_key, limit_type)
      
      status.should_not be_nil
      status.not_nil!["limit"].should eq(2000)
      status.not_nil!["remaining"].should eq(1998)
    end
    
    it "gets top endpoints correctly" do
      date = Date.utc
      analytics_key = "analytics:#{date.to_s("%Y-%m-%d")}"
      
      # Create test data with different endpoints
      [
        "/api/v1/shards",
        "/api/v1/shards",
        "/api/v1/search",
        "/api/v1/search",
        "/api/v1/search"
      ].each_with_index do |path, i|
        request_data = {
          timestamp: Time.utc.to_unix,
          path: path,
          method: "GET",
          rate_key: "anon:127.0.0.1",
          user_agent: "test",
          authenticated: false
        }
        redis.lpush(analytics_key, request_data.to_json)
      end
      
      top_endpoints = analytics_service.get_top_endpoints(date, 10)
      
      top_endpoints.size.should eq(2)
      top_endpoints[0][0].should eq("/api/v1/search")  # Most popular
      top_endpoints[0][1].should eq(3)                  # 3 requests
      top_endpoints[1][0].should eq("/api/v1/shards")   # Second most popular
      top_endpoints[1][1].should eq(2)                  # 2 requests
    end
    
    it "cleans up old data correctly" do
      # Create old analytics data
      old_date = Date.utc - 35.days
      old_key = "analytics:#{old_date.to_s("%Y-%m-%d")}"
      redis.set(old_key, "old_data")
      
      # Create recent data
      recent_date = Date.utc - 5.days
      recent_key = "analytics:#{recent_date.to_s("%Y-%m-%d")}"
      redis.set(recent_key, "recent_data")
      
      # Clean up data older than 30 days
      analytics_service.cleanup_old_data(30)
      
      # Old data should be deleted
      redis.exists(old_key).should eq(0)
      
      # Recent data should remain
      redis.exists(recent_key).should eq(1)
    end
  end
end