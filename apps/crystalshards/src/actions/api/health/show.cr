require "redis"

class Api::Health::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/health" do
    db_status = check_database
    redis_status = check_redis

    # Return 503 Service Unavailable if any critical service is unhealthy
    # This ensures Kubernetes health checks properly fail
    all_healthy = !db_status.starts_with?("unhealthy") && !redis_status.starts_with?("unhealthy")

    context.response.status_code = all_healthy ? 200 : 503

    json({
      status:    all_healthy ? "ok" : "degraded",
      version:   "0.1.0",
      timestamp: Time.utc.to_rfc3339,
      services:  {
        database: db_status,
        redis:    redis_status,
      },
    })
  end

  private def check_database : String
    AppDatabase.run do |db|
      db.query_one "SELECT 1", as: Int32
    end
    "healthy"
  rescue ex
    "unhealthy: #{ex.message}"
  end

  private def check_redis : String
    redis = Redis.new(url: ENV["REDIS_URL"]? || "redis://localhost:6379")
    # Try a simple operation to check connection
    redis.ping
    "healthy"
  rescue ex
    "unhealthy: #{ex.message}"
  ensure
    redis.try(&.close)
  end
end
