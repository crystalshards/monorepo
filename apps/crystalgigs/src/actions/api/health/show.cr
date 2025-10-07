class Api::Health::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/health" do
    json({
      status:    "ok",
      version:   "0.1.0",
      timestamp: Time.utc.to_rfc3339,
      services:  {
        database: check_database,
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
end
