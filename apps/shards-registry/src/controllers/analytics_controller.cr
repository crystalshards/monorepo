require "kemal"
require "../middleware/rate_limit_middleware"

module CrystalShards
  # API endpoints for usage analytics and rate limiting information
  class AnalyticsController
    
    def self.setup_routes(redis : Redis)
      analytics_service = UsageAnalyticsService.new(redis)
      
      # Get usage statistics (admin only)
      get "/api/analytics/usage" do |env|
        user = require_admin(env)
        next unless user
        
        # Parse date range parameters
        start_date_str = env.params.query["start_date"]? || (Date.utc - 7.days).to_s
        end_date_str = env.params.query["end_date"]? || Date.utc.to_s
        
        begin
          start_date = Date.parse(start_date_str, "%Y-%m-%d")
          end_date = Date.parse(end_date_str, "%Y-%m-%d")
          
          if end_date < start_date
            env.response.status_code = 400
            env.response.content_type = "application/json"
            next {error: "end_date must be after start_date"}.to_json
          end
          
          if (end_date - start_date).total_days > 30
            env.response.status_code = 400
            env.response.content_type = "application/json"
            next {error: "Date range cannot exceed 30 days"}.to_json
          end
          
          stats = analytics_service.get_usage_stats(start_date, end_date)
          
          env.response.content_type = "application/json"
          {
            start_date: start_date.to_s,
            end_date: end_date.to_s,
            stats: stats
          }.to_json
          
        rescue ex : ArgumentError
          env.response.status_code = 400
          env.response.content_type = "application/json"
          {error: "Invalid date format. Use YYYY-MM-DD"}.to_json
        rescue ex
          env.response.status_code = 500
          env.response.content_type = "application/json"
          {error: "Failed to retrieve analytics data"}.to_json
        end
      end
      
      # Get top endpoints by usage (admin only)
      get "/api/analytics/top-endpoints" do |env|
        user = require_admin(env)
        next unless user
        
        date_str = env.params.query["date"]? || Date.utc.to_s
        limit = env.params.query["limit"]?.try(&.to_i) || 10
        
        begin
          date = Date.parse(date_str, "%Y-%m-%d")
          
          if limit < 1 || limit > 100
            env.response.status_code = 400
            env.response.content_type = "application/json"
            next {error: "Limit must be between 1 and 100"}.to_json
          end
          
          top_endpoints = analytics_service.get_top_endpoints(date, limit)
          
          env.response.content_type = "application/json"
          {
            date: date.to_s,
            top_endpoints: top_endpoints.map { |endpoint, count|
              {endpoint: endpoint, requests: count}
            }
          }.to_json
          
        rescue ex : ArgumentError
          env.response.status_code = 400
          env.response.content_type = "application/json"
          {error: "Invalid date format. Use YYYY-MM-DD"}.to_json
        rescue ex
          env.response.status_code = 500
          env.response.content_type = "application/json"
          {error: "Failed to retrieve endpoint analytics"}.to_json
        end
      end
      
      # Get current user's rate limit status
      get "/api/analytics/rate-limit-status" do |env|
        # Allow both authenticated users and API keys to check their status
        api_key = env.get?("current_api_key").as(AuthenticatedApiKey?)
        user = env.get?("current_user").as(AuthenticatedUser?)
        
        unless api_key || user
          env.response.status_code = 401
          env.response.content_type = "application/json"
          next {error: "Authentication required"}.to_json
        end
        
        begin
          # Determine rate key and limit type based on authentication method
          if api_key
            if api_key.scopes.includes?("admin")
              rate_key = "api_key:#{api_key.key_hash}:admin"
              limit_type = "api_key_admin"
            elsif api_key.scopes.includes?("shards:write")
              rate_key = "api_key:#{api_key.key_hash}:write"
              limit_type = "api_key_write"
            else
              rate_key = "api_key:#{api_key.key_hash}:read"
              limit_type = "api_key_read"
            end
          elsif user
            rate_key = "jwt:#{user.id}"
            limit_type = "jwt_authenticated"
          end
          
          # Get hourly and burst limits
          hourly_status = analytics_service.get_rate_limit_status(rate_key, limit_type)
          burst_status = analytics_service.get_rate_limit_status("#{rate_key}:burst", "burst_authenticated")
          
          env.response.content_type = "application/json"
          {
            hourly: hourly_status,
            burst: burst_status,
            authentication_type: api_key ? "api_key" : "jwt",
            scopes: api_key ? api_key.scopes : ["full_access"]
          }.to_json
          
        rescue ex
          env.response.status_code = 500
          env.response.content_type = "application/json"
          {error: "Failed to retrieve rate limit status"}.to_json
        end
      end
      
      # Get rate limit information for public display
      get "/api/analytics/rate-limits" do |env|
        # Public endpoint showing rate limit tiers
        
        env.response.content_type = "application/json"
        {
          rate_limits: {
            anonymous: {
              description: "Unauthenticated requests",
              hourly_limit: RateLimitMiddleware::LIMITS["anonymous"][:requests],
              burst_limit: RateLimitMiddleware::LIMITS["burst_anonymous"][:requests],
              search_hourly_limit: RateLimitMiddleware::LIMITS["anonymous_search"][:requests]
            },
            jwt_authenticated: {
              description: "Authenticated users with JWT tokens",
              hourly_limit: RateLimitMiddleware::LIMITS["jwt_authenticated"][:requests],
              burst_limit: RateLimitMiddleware::LIMITS["burst_authenticated"][:requests]
            },
            api_key_read: {
              description: "API keys with read-only access",
              hourly_limit: RateLimitMiddleware::LIMITS["api_key_read"][:requests],
              burst_limit: RateLimitMiddleware::LIMITS["burst_authenticated"][:requests]
            },
            api_key_write: {
              description: "API keys with write access to shards",
              hourly_limit: RateLimitMiddleware::LIMITS["api_key_write"][:requests],
              burst_limit: RateLimitMiddleware::LIMITS["burst_authenticated"][:requests]
            },
            api_key_admin: {
              description: "API keys with admin access",
              hourly_limit: RateLimitMiddleware::LIMITS["api_key_admin"][:requests],
              burst_limit: RateLimitMiddleware::LIMITS["burst_authenticated"][:requests]
            }
          },
          documentation: "https://docs.crystalshards.org/api/rate-limits",
          headers: {
            limit: "X-RateLimit-Limit",
            remaining: "X-RateLimit-Remaining", 
            reset: "X-RateLimit-Reset",
            window: "X-RateLimit-Window"
          }
        }.to_json
      end
      
      # Analytics cleanup endpoint (admin only, typically called by background job)
      post "/api/analytics/cleanup" do |env|
        user = require_admin(env)
        next unless user
        
        days_to_keep = env.params.json["days_to_keep"]?.try(&.as_i) || 30
        
        if days_to_keep < 1 || days_to_keep > 365
          env.response.status_code = 400
          env.response.content_type = "application/json"
          next {error: "days_to_keep must be between 1 and 365"}.to_json
        end
        
        begin
          analytics_service.cleanup_old_data(days_to_keep)
          
          env.response.content_type = "application/json"
          {
            message: "Analytics cleanup completed",
            days_kept: days_to_keep,
            timestamp: Time.utc.to_rfc3339
          }.to_json
          
        rescue ex
          env.response.status_code = 500
          env.response.content_type = "application/json"
          {error: "Failed to cleanup analytics data"}.to_json
        end
      end
    end
  end
end