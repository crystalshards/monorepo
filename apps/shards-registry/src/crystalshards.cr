require "kemal"
require "pg"
require "redis"
require "jwt"
require "dotenv"
require "yaml"
require "openssl/hmac"
require "digest/md5"
require "base64"
require "./models/auth_models"
require "./repositories/shard_repository"
require "./search_options"
require "./services/shard_submission_service"
require "./services/search_analytics_service"
require "./middleware/auth_middleware"
require "./controllers/auth_controller"
require "./metrics"

# Load environment variables
Dotenv.load

module CrystalShards
  VERSION = "0.1.0"
  
  # Configuration
  DATABASE_URL = ENV["DATABASE_URL"]? || "postgres://postgres:password@localhost/crystalshards_development"
  REDIS_URL = ENV["REDIS_URL"]? || "redis://localhost:6379"
  
  # Initialize database connection
  DB = PG.connect(DATABASE_URL)
  
  # Initialize Redis connection
  REDIS = Redis.new(url: REDIS_URL)
  
  # Initialize services
  shard_repo = ShardRepository.new(DB)
  submission_service = ShardSubmissionService.new(DB, REDIS)
  analytics_service = SearchAnalyticsService.new(REDIS)
  
  # Add authentication middleware
  add_handler CrystalShards::AuthMiddleware.new
  
  # Add metrics middleware
  add_handler Metrics::MetricsHandler.new
  
  # Helper function to verify GitHub webhook signatures
  def verify_github_signature(payload : String?, signature : String, secret : String) : Bool
    return false unless payload && signature.starts_with?("sha256=")
    
    expected_signature = "sha256=" + OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, secret, payload)
    
    # Constant-time comparison to prevent timing attacks
    signature.size == expected_signature.size &&
      signature.chars.zip(expected_signature.chars).all? { |a, b| a == b }
  rescue
    false
  end
  
  # Health check endpoint
  get "/health" do |env|
    env.response.content_type = "application/json"
    {
      status: "ok",
      version: VERSION,
      timestamp: Time.utc.to_s
    }.to_json
  end
  
  # Prometheus metrics endpoint
  get "/metrics" do |env|
    env.response.content_type = "text/plain; version=0.0.4; charset=utf-8"
    
    # Update database connections gauge
    begin
      result = DB.query("SELECT count(*) FROM pg_stat_activity")
      result.each do |row|
        Metrics::DATABASE_CONNECTIONS.set(row[0].as(Int64).to_f64)
      end
    rescue
      # Ignore database errors for metrics collection
    end
    
    Metrics::REGISTRY.to_prometheus
  end
  
  # API root
  get "/api/v1" do |env|
    env.response.content_type = "application/json"
    {
      message: "CrystalShards API v1",
      version: VERSION,
      endpoints: {
        shards: "/api/v1/shards",
        "shard_detail": "/api/v1/shards/:name",
        "submit_shard": "POST /api/v1/shards",
        search: "/api/v1/search",
        filters: "/api/v1/search/filters",
        suggestions: "/api/v1/search/suggestions",
        trending: "/api/v1/search/trending",
        popular: "/api/v1/search/popular",
        analytics: "/api/v1/search/analytics",
        webhooks: "/webhooks/github",
        health: "/health"
      },
      documentation: "https://docs.crystalshards.org/api"
    }.to_json
  end
  
  # Shards listing endpoint
  get "/api/v1/shards" do |env|
    env.response.content_type = "application/json"
    
    page = env.params.query["page"]?.try(&.to_i) || 1
    per_page = [env.params.query["per_page"]?.try(&.to_i) || 20, 100].min
    offset = (page - 1) * per_page
    
    begin
      shards = shard_repo.list_published(offset, per_page)
      total = shard_repo.count_published
      
      {
        shards: shards.map(&.to_json),
        total: total,
        page: page,
        per_page: per_page,
        pages: (total / per_page.to_f).ceil.to_i
      }.to_json
    rescue ex
      env.response.status_code = 500
      {error: "Database error", message: ex.message}.to_json
    end
  end
  
  # Search endpoint
  get "/api/v1/search" do |env|
    env.response.content_type = "application/json"
    query = env.params.query["q"]? || ""
    
    # Parse search options from query parameters
    search_options = SearchOptions.from_params(env.params.query.to_h)
    
    # Validate sort parameter
    unless search_options.valid_sort_by?
      env.response.status_code = 400
      {error: "Invalid sort_by parameter. Valid options: relevance, stars, downloads, recent, name"}.to_json
    else
      page = env.params.query["page"]?.try(&.to_i) || 1
      per_page = [env.params.query["per_page"]?.try(&.to_i) || 20, 100].min
      offset = (page - 1) * per_page
      
      begin
        search_start = Time.utc
        
        # Check if highlights are requested
        highlight = env.params.query["highlight"]? == "true"
        
        if highlight && !query.empty?
          # Use highlighting search for better user experience
          highlighted_results = shard_repo.search_with_highlights(query, offset, per_page, search_options)
          total = shard_repo.count_search(query, search_options)
          search_duration = (Time.utc - search_start).total_seconds
          Metrics::SEARCH_DURATION.observe(search_duration)
          
          # Record search analytics (non-blocking)
          spawn do
            begin
              user_ip = env.request.headers["X-Forwarded-For"]? || env.request.remote_address.to_s
              user_id = Digest::MD5.hexdigest(user_ip)
              analytics_service.record_search(query, total, user_id, search_options)
            rescue ex
              puts "Search analytics recording failed: #{ex.message}"
            end
          end
          
          {
            query: query,
            filters: search_options,
            results: highlighted_results,
            total: total,
            page: page,
            per_page: per_page,
            pages: (total / per_page.to_f).ceil.to_i,
            highlights_enabled: true
          }.to_json
        else
          # Regular search without highlights
          results = shard_repo.search(query, offset, per_page, search_options)
          total = shard_repo.count_search(query, search_options)
          search_duration = (Time.utc - search_start).total_seconds
          Metrics::SEARCH_DURATION.observe(search_duration)
          
          # Record search analytics (non-blocking)
          spawn do
            begin
              user_ip = env.request.headers["X-Forwarded-For"]? || env.request.remote_address.to_s
              user_id = Digest::MD5.hexdigest(user_ip)
              analytics_service.record_search(query, total, user_id, search_options)
            rescue ex
              puts "Search analytics recording failed: #{ex.message}"
            end
          end
          
          {
            query: query,
            filters: search_options,
            results: results.map(&.to_json),
            total: total,
            page: page,
            per_page: per_page,
            pages: (total / per_page.to_f).ceil.to_i,
            highlights_enabled: false
          }.to_json
        end
      rescue ex
        env.response.status_code = 500
        {error: "Search error", message: ex.message}.to_json
      end
    end
  end

  # Search filters endpoint - returns available filter values
  get "/api/v1/search/filters" do |env|
    env.response.content_type = "application/json"
    
    begin
      filters = shard_repo.get_available_filters
      filters.to_json
    rescue ex
      env.response.status_code = 500
      {error: "Filters error", message: ex.message}.to_json
    end
  end

  # Search suggestions endpoint - returns autocomplete suggestions
  get "/api/v1/search/suggestions" do |env|
    env.response.content_type = "application/json"
    query = env.params.query["q"]? || ""
    limit = [env.params.query["limit"]?.try(&.to_i) || 10, 50].min
    
    begin
      suggestions = shard_repo.get_search_suggestions(query, limit)
      {
        query: query,
        suggestions: suggestions
      }.to_json
    rescue ex
      env.response.status_code = 500
      {error: "Suggestions error", message: ex.message}.to_json
    end
  end

  # Search trending endpoint - returns trending searches
  get "/api/v1/search/trending" do |env|
    env.response.content_type = "application/json"
    limit = [env.params.query["limit"]?.try(&.to_i) || 20, 100].min
    
    begin
      trending = analytics_service.get_trending_searches(limit)
      {
        trending_searches: trending,
        period: "last_7_days"
      }.to_json
    rescue ex
      env.response.status_code = 500
      {error: "Trending search error", message: ex.message}.to_json
    end
  end

  # Search popular endpoint - returns most popular searches by count
  get "/api/v1/search/popular" do |env|
    env.response.content_type = "application/json"
    limit = [env.params.query["limit"]?.try(&.to_i) || 20, 100].min
    
    begin
      popular = analytics_service.get_popular_searches(limit)
      {
        popular_searches: popular,
        period: "all_time"
      }.to_json
    rescue ex
      env.response.status_code = 500
      {error: "Popular search error", message: ex.message}.to_json
    end
  end

  # Search analytics endpoint - returns detailed search statistics
  get "/api/v1/search/analytics" do |env|
    env.response.content_type = "application/json"
    days_back = [env.params.query["days"]?.try(&.to_i) || 7, 30].min
    
    begin
      stats = analytics_service.get_search_stats(days_back)
      trending = analytics_service.get_trending_searches(10)
      popular = analytics_service.get_popular_searches(10)
      recent = analytics_service.get_recent_searches(20)
      
      {
        statistics: stats,
        trending_searches: trending,
        popular_searches: popular,
        recent_searches: recent,
        period: "last_#{days_back}_days"
      }.to_json
    rescue ex
      env.response.status_code = 500
      {error: "Analytics error", message: ex.message}.to_json
    end
  end
  
  # Shard submission endpoint (requires authentication)
  post "/api/v1/shards" do |env|
    env.response.content_type = "application/json"
    
    # Require authentication for shard submission
    user = CrystalShards.require_auth(env)
    next if user.nil?
    
    # Check API key scope if using API key authentication
    unless CrystalShards.check_api_scope(env, "shards:write")
      env.response.status_code = 403
      next {error: "Insufficient permissions. Required scope: shards:write"}.to_json
    end
    
    # Parse request body
    begin
      body = JSON.parse(env.request.body || "{}")
      github_url = body["github_url"]?.try(&.as_s)
      
      unless github_url
        env.response.status_code = 400
        next {error: "Missing required field: github_url"}.to_json
      end
      
      # Check for recent submission
      if submission_service.recently_submitted?(github_url)
        env.response.status_code = 429
        next {error: "This repository was already submitted recently. Please wait before trying again."}.to_json
      end
      
      # Submit the shard
      result = submission_service.submit_from_github(github_url)
      
      # Track shard submission
      if result[:shard]
        Metrics::SHARD_SUBMISSIONS_TOTAL.increment
      end
      
      if result[:shard]
        if result[:errors].empty?
          env.response.status_code = 201
          {
            message: "Shard submitted successfully",
            shard: result[:shard].try(&.to_json),
            status: "pending_review"
          }.to_json
        else
          env.response.status_code = 409
          {
            message: "Shard already exists",
            shard: result[:shard].try(&.to_json),
            errors: result[:errors]
          }.to_json
        end
      else
        env.response.status_code = 422
        {
          error: "Failed to submit shard",
          errors: result[:errors]
        }.to_json
      end
    rescue JSON::ParseException
      env.response.status_code = 400
      {error: "Invalid JSON in request body"}.to_json
    rescue ex
      env.response.status_code = 500
      {error: "Internal server error", message: ex.message}.to_json
    end
  end
  
  # Individual shard endpoint
  get "/api/v1/shards/:name" do |env|
    env.response.content_type = "application/json"
    name = env.params.url["name"]
    
    begin
      shard = shard_repo.find_by_name(name)
      if shard && shard.published
        shard.to_json
      else
        env.response.status_code = 404
        {error: "Shard not found"}.to_json
      end
    rescue ex
      env.response.status_code = 500
      {error: "Database error", message: ex.message}.to_json
    end
  end
  
  # GitHub webhook endpoint for automatic updates
  post "/webhooks/github" do |env|
    env.response.content_type = "application/json"
    
    # Verify GitHub webhook signature if secret is configured
    github_secret = ENV["GITHUB_WEBHOOK_SECRET"]?
    if github_secret
      signature = env.request.headers["X-Hub-Signature-256"]?
      unless signature && verify_github_signature(env.request.body, signature, github_secret)
        env.response.status_code = 401
        next {error: "Invalid signature"}.to_json
      end
    end
    
    begin
      payload = JSON.parse(env.request.body || "{}")
      
      # Handle push events for version updates
      if payload["action"]? == "published" || payload["ref"]? == "refs/heads/main"
        repository = payload["repository"]?
        if repository
          github_url = repository["html_url"]?.try(&.as_s)
          if github_url
            if shard = shard_repo.find_by_github_url(github_url)
              # Update GitHub stats
              submission_service.update_github_stats(shard.id.not_nil!)
            end
          end
        end
      end
      
      {status: "ok"}.to_json
    rescue JSON::ParseException
      env.response.status_code = 400
      {error: "Invalid JSON payload"}.to_json
    rescue ex
      env.response.status_code = 500
      {error: "Webhook processing error", message: ex.message}.to_json
    end
  end
  
  # CORS middleware
  before_all do |env|
    env.response.headers["Access-Control-Allow-Origin"] = "*"
    env.response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
    env.response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
  end
  
  # Handle OPTIONS requests
  options "/*" do |env|
    env.response.status_code = 200
  end
  
  # Error handler
  error 404 do |env|
    env.response.content_type = "application/json"
    {
      error: "Not Found",
      status: 404
    }.to_json
  end
  
  error 500 do |env|
    env.response.content_type = "application/json"
    {
      error: "Internal Server Error",
      status: 500
    }.to_json
  end
end

# Start the server
port = ENV["PORT"]?.try(&.to_i) || 3000
puts "Starting CrystalShards Registry on port #{port}"
Kemal.run(port)