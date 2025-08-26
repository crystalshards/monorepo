require "kemal"
require "redis"
require "json"

module CrystalShards
  # Rate limiting middleware with per-user and per-IP limits
  class RateLimitMiddleware < Kemal::Handler
    
    # Rate limit configurations
    LIMITS = {
      # API key limits (per hour)
      "api_key_admin" => {requests: 10000, window: 3600},
      "api_key_write" => {requests: 1000, window: 3600},
      "api_key_read" => {requests: 5000, window: 3600},
      
      # JWT user limits (per hour)
      "jwt_authenticated" => {requests: 2000, window: 3600},
      
      # Anonymous limits (per hour)
      "anonymous" => {requests: 100, window: 3600},
      "anonymous_search" => {requests: 500, window: 3600},
      
      # Per-minute burst limits
      "burst_authenticated" => {requests: 60, window: 60},
      "burst_anonymous" => {requests: 10, window: 60}
    }
    
    def initialize(@redis : Redis)
    end
    
    def call(env)
      # Skip rate limiting for health checks
      return call_next(env) if env.request.path.starts_with?("/health") || env.request.path.starts_with?("/ready")
      
      # Determine rate limit key and limits
      rate_key, limits = get_rate_limit_config(env)
      
      # Check hourly limit
      if !check_rate_limit(rate_key, limits[:requests], limits[:window])
        return rate_limit_exceeded(env, limits[:window])
      end
      
      # Check burst limit for all requests
      burst_key = "#{rate_key}:burst"
      burst_limits = is_authenticated?(env) ? LIMITS["burst_authenticated"] : LIMITS["burst_anonymous"]
      
      if !check_rate_limit(burst_key, burst_limits[:requests], burst_limits[:window])
        return rate_limit_exceeded(env, burst_limits[:window])
      end
      
      # Record usage analytics
      record_usage_analytics(env, rate_key)
      
      # Add rate limit headers
      add_rate_limit_headers(env, rate_key, limits)
      
      call_next(env)
    end
    
    private def get_rate_limit_config(env)
      # Check if user is authenticated via API key
      if api_key = env.get?("current_api_key").as(AuthenticatedApiKey?)
        if api_key.scopes.includes?("admin")
          key = "api_key:#{api_key.key_hash}:admin"
          limits = LIMITS["api_key_admin"]
        elsif api_key.scopes.includes?("shards:write")
          key = "api_key:#{api_key.key_hash}:write"
          limits = LIMITS["api_key_write"]
        else
          key = "api_key:#{api_key.key_hash}:read"
          limits = LIMITS["api_key_read"]
        end
        return {key, limits}
      end
      
      # Check if user is authenticated via JWT
      if user = env.get?("current_user").as(AuthenticatedUser?)
        key = "jwt:#{user.id}"
        limits = LIMITS["jwt_authenticated"]
        return {key, limits}
      end
      
      # Anonymous user - use IP-based limiting
      ip = get_client_ip(env)
      
      # Higher limits for search endpoints
      if env.request.path.starts_with?("/api/search")
        key = "anon:#{ip}:search"
        limits = LIMITS["anonymous_search"]
      else
        key = "anon:#{ip}"
        limits = LIMITS["anonymous"]
      end
      
      {key, limits}
    end
    
    private def check_rate_limit(key : String, limit : Int32, window : Int32) : Bool
      current_time = Time.utc.to_unix
      window_start = current_time - window
      
      # Use Redis sliding window counter
      @redis.pipelined do |pipe|
        # Remove expired entries
        pipe.zremrangebyscore(key, "-inf", window_start.to_s)
        
        # Count current requests
        pipe.zcard(key)
        
        # Add current request
        pipe.zadd(key, current_time, "#{current_time}-#{Random.rand(1000)}")
        
        # Set expiration
        pipe.expire(key, window)
      end
      
      current_count = @redis.zcard(key)
      current_count < limit
    end
    
    private def record_usage_analytics(env, rate_key : String)
      begin
        # Record analytics data
        analytics_key = "analytics:#{Date.utc.to_s("%Y-%m-%d")}"
        
        analytics_data = {
          timestamp: Time.utc.to_unix,
          path: env.request.path,
          method: env.request.method,
          rate_key: rate_key,
          user_agent: env.request.headers["User-Agent"]? || "unknown",
          authenticated: is_authenticated?(env)
        }
        
        @redis.lpush(analytics_key, analytics_data.to_json)
        @redis.expire(analytics_key, 86400 * 30) # Keep for 30 days
      rescue ex
        Log.warn { "Failed to record usage analytics: #{ex.message}" }
      end
    end
    
    private def add_rate_limit_headers(env, rate_key : String, limits)
      begin
        current_count = @redis.zcard(rate_key)
        remaining = [limits[:requests] - current_count, 0].max
        
        env.response.headers["X-RateLimit-Limit"] = limits[:requests].to_s
        env.response.headers["X-RateLimit-Remaining"] = remaining.to_s
        env.response.headers["X-RateLimit-Reset"] = (Time.utc.to_unix + limits[:window]).to_s
        env.response.headers["X-RateLimit-Window"] = limits[:window].to_s
      rescue ex
        Log.warn { "Failed to add rate limit headers: #{ex.message}" }
      end
    end
    
    private def rate_limit_exceeded(env, window : Int32)
      env.response.status_code = 429
      env.response.content_type = "application/json"
      
      retry_after = window
      env.response.headers["Retry-After"] = retry_after.to_s
      
      error_response = {
        error: "Rate limit exceeded",
        message: "Too many requests. Please try again later.",
        retry_after_seconds: retry_after,
        documentation: "https://docs.crystalshards.org/api/rate-limits"
      }
      
      env.response.print(error_response.to_json)
      env
    end
    
    private def is_authenticated?(env) : Bool
      env.get?("current_user") || env.get?("current_api_key")
    end
    
    private def get_client_ip(env) : String
      # Check for forwarded IP headers (common in production behind proxies)
      forwarded_for = env.request.headers["X-Forwarded-For"]?
      if forwarded_for
        # Take the first IP from the comma-separated list
        return forwarded_for.split(",").first.strip
      end
      
      real_ip = env.request.headers["X-Real-IP"]?
      return real_ip if real_ip
      
      # Fallback to remote address
      env.request.remote_address || "unknown"
    end
  end
  
  # Usage analytics service
  class UsageAnalyticsService
    def initialize(@redis : Redis)
    end
    
    # Get usage statistics for a date range
    def get_usage_stats(start_date : Date, end_date : Date)
      stats = {} of String => Hash(String, Int32 | String)
      
      current_date = start_date
      while current_date <= end_date
        analytics_key = "analytics:#{current_date.to_s("%Y-%m-%d")}"
        
        # Get all requests for this date
        requests = @redis.lrange(analytics_key, 0, -1)
        
        daily_stats = {
          "total_requests" => 0,
          "authenticated_requests" => 0,
          "anonymous_requests" => 0,
          "api_key_requests" => 0,
          "jwt_requests" => 0,
          "unique_ips" => Set(String).new,
          "endpoints" => Hash(String, Int32).new,
          "methods" => Hash(String, Int32).new
        }
        
        requests.each do |request_json|
          begin
            data = JSON.parse(request_json)
            daily_stats["total_requests"] = daily_stats["total_requests"].as(Int32) + 1
            
            if data["authenticated"].as_bool
              daily_stats["authenticated_requests"] = daily_stats["authenticated_requests"].as(Int32) + 1
              
              if data["rate_key"].as_s.starts_with?("api_key")
                daily_stats["api_key_requests"] = daily_stats["api_key_requests"].as(Int32) + 1
              elsif data["rate_key"].as_s.starts_with?("jwt")
                daily_stats["jwt_requests"] = daily_stats["jwt_requests"].as(Int32) + 1
              end
            else
              daily_stats["anonymous_requests"] = daily_stats["anonymous_requests"].as(Int32) + 1
            end
            
            # Extract IP from rate key for anonymous requests
            if data["rate_key"].as_s.starts_with?("anon:")
              ip = data["rate_key"].as_s.split(":")[1]
              daily_stats["unique_ips"].as(Set(String)).add(ip)
            end
            
            # Track endpoints and methods
            path = data["path"].as_s
            method = data["method"].as_s
            
            endpoints = daily_stats["endpoints"].as(Hash(String, Int32))
            endpoints[path] = endpoints.fetch(path, 0) + 1
            
            methods = daily_stats["methods"].as(Hash(String, Int32))
            methods[method] = methods.fetch(method, 0) + 1
            
          rescue ex
            Log.warn { "Failed to parse analytics data: #{ex.message}" }
          end
        end
        
        # Convert set size to count
        daily_stats["unique_ips"] = daily_stats["unique_ips"].as(Set(String)).size
        
        stats[current_date.to_s] = daily_stats.transform_values { |v|
          case v
          when Set
            v.size
          when Hash
            v
          else
            v
          end
        }.as(Hash(String, Int32 | String | Hash(String, Int32)))
        
        current_date += 1.day
      end
      
      stats
    end
    
    # Get current rate limit status for a user/API key
    def get_rate_limit_status(rate_key : String, limit_type : String)
      limits = RateLimitMiddleware::LIMITS[limit_type]?
      return nil unless limits
      
      current_count = @redis.zcard(rate_key)
      remaining = [limits[:requests] - current_count, 0].max
      
      {
        limit: limits[:requests],
        remaining: remaining,
        reset_at: Time.utc.to_unix + limits[:window],
        window_seconds: limits[:window]
      }
    end
    
    # Get top endpoints by usage
    def get_top_endpoints(date : Date, limit = 10)
      analytics_key = "analytics:#{date.to_s("%Y-%m-%d")}"
      requests = @redis.lrange(analytics_key, 0, -1)
      
      endpoint_counts = Hash(String, Int32).new
      
      requests.each do |request_json|
        begin
          data = JSON.parse(request_json)
          path = data["path"].as_s
          endpoint_counts[path] = endpoint_counts.fetch(path, 0) + 1
        rescue ex
          Log.warn { "Failed to parse analytics data: #{ex.message}" }
        end
      end
      
      endpoint_counts.to_a.sort_by(&.[1]).reverse.first(limit)
    end
    
    # Clean up old analytics data (called by background job)
    def cleanup_old_data(days_to_keep = 30)
      cutoff_date = Date.utc - days_to_keep.days
      
      # Find all analytics keys older than cutoff
      pattern = "analytics:*"
      keys = @redis.keys(pattern)
      
      keys.each do |key|
        if matches = key.match(/analytics:(\d{4}-\d{2}-\d{2})/)
          key_date = Date.parse(matches[1], "%Y-%m-%d")
          if key_date < cutoff_date
            @redis.del(key)
            Log.info { "Deleted old analytics data: #{key}" }
          end
        end
      end
    end
  end
end