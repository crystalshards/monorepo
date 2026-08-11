class Api::Health::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/health" do
    db_status = check_database

    # 503 when a service this app genuinely cannot serve without is down.
    #
    # That list is exactly one entry long, and keeping it that short is the
    # point. This endpoint is the Cloud Run startup probe, so anything named
    # here can refuse to promote a revision. Object storage and the build queue
    # are deliberately absent: a docs build that cannot be commissioned is a
    # degraded feature on one page, and rolling back a good deploy over it
    # would take the whole site down to protect a background job.
    all_healthy = !db_status.starts_with?("unhealthy")

    context.response.status_code = all_healthy ? 200 : 503

    json({
      status:    all_healthy ? "ok" : "degraded",
      version:   "0.1.0",
      timestamp: Time.utc.to_rfc3339,
      services:  {
        database: db_status,
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
