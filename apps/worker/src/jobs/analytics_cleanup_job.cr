require "sidekiq"
require "redis"

# Analytics cleanup job - removes old usage analytics data
class AnalyticsCleanupJob
  include Sidekiq::Worker
  
  def perform(days_to_keep : Int32 = 30)
    redis = Redis.new(url: ENV["REDIS_URL"]? || "redis://localhost:6379")
    
    begin
      # Clean up analytics data older than specified days
      cleanup_analytics_data(redis, days_to_keep)
      
      # Clean up rate limiting data older than 7 days
      cleanup_rate_limit_data(redis, 7)
      
      Log.info { "Analytics cleanup completed successfully. Kept #{days_to_keep} days of data." }
      
    rescue ex
      Log.error { "Analytics cleanup failed: #{ex.message}" }
      raise ex
    ensure
      redis.close
    end
  end
  
  private def cleanup_analytics_data(redis : Redis, days_to_keep : Int32)
    cutoff_date = Date.utc - days_to_keep.days
    
    # Find all analytics keys older than cutoff
    pattern = "analytics:*"
    keys = redis.keys(pattern)
    deleted_count = 0
    
    keys.each do |key|
      if matches = key.match(/analytics:(\d{4}-\d{2}-\d{2})/)
        begin
          key_date = Date.parse(matches[1], "%Y-%m-%d")
          if key_date < cutoff_date
            redis.del(key)
            deleted_count += 1
            Log.info { "Deleted old analytics data: #{key}" }
          end
        rescue Date::Error
          Log.warn { "Invalid date format in key: #{key}" }
        end
      end
    end
    
    Log.info { "Cleaned up #{deleted_count} old analytics keys" }
  end
  
  private def cleanup_rate_limit_data(redis : Redis, days_to_keep : Int32)
    cutoff_timestamp = Time.utc.to_unix - (days_to_keep * 86400)
    
    # Find all rate limiting keys
    rate_patterns = ["api_key:*", "jwt:*", "anon:*"]
    deleted_count = 0
    
    rate_patterns.each do |pattern|
      keys = redis.keys(pattern)
      
      keys.each do |key|
        # Skip if not a rate limit key (should contain timestamps)
        next unless redis.type(key) == "zset"
        
        begin
          # Remove entries older than cutoff
          removed = redis.zremrangebyscore(key, "-inf", cutoff_timestamp.to_s)
          
          # Delete the key if it's empty
          if redis.zcard(key) == 0
            redis.del(key)
            deleted_count += 1
          end
        rescue ex
          Log.warn { "Error cleaning rate limit key #{key}: #{ex.message}" }
        end
      end
    end
    
    Log.info { "Cleaned up #{deleted_count} empty rate limit keys" }
  end
end

# Schedule the job to run daily at 2 AM UTC
# This would typically be configured in a cron job or scheduler like:
# AnalyticsCleanupJob.perform_at(Time.utc.at_beginning_of_day + 2.hours, 30)