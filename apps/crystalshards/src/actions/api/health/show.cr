class Api::Health::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/health" do
    json({
      status:    "ok",
      version:   "0.1.0",
      timestamp: Time.utc.to_rfc3339,
      services:  {
        database: check_database,
        redis:    check_redis,
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
    redis = Redis::Client.new(uri: URI.parse(ENV["REDIS_URL"]? || "redis://localhost:6379"))
    redis.ping
    "healthy"
  rescue ex
    "unhealthy: #{ex.message}"
  ensure
    redis.try(&.close)
  end
end
