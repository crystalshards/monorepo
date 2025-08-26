require "sidekiq/job"
require "../../../shards-registry/src/services/search_analytics_service"

class SearchAnalyticsCleanupJob
  include Sidekiq::Job

  def perform
    puts "Starting search analytics cleanup job..."
    
    begin
      # Initialize Redis connection
      redis_url = ENV["REDIS_URL"]? || "redis://localhost:6379"
      redis = Redis.new(url: redis_url)
      
      # Initialize analytics service
      analytics_service = CrystalShards::SearchAnalyticsService.new(redis)
      
      # Run cleanup
      analytics_service.cleanup_old_data
      
      puts "Search analytics cleanup completed successfully"
    rescue ex
      puts "Search analytics cleanup failed: #{ex.message}"
      raise ex
    ensure
      redis.try(&.close) if redis
    end
  end
end