require "kemal"
require "pg"
require "redis"
require "jwt"
require "dotenv"
require "yaml"
require "openssl/hmac"
require "digest/md5"
require "base64"
require "./repositories/shard_repository"
require "./services/shard_submission_service"
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
    
    if query.empty?
      env.response.status_code = 400
      {error: "Missing query parameter 'q'"}.to_json
    else
      page = env.params.query["page"]?.try(&.to_i) || 1
      per_page = [env.params.query["per_page"]?.try(&.to_i) || 20, 100].min
      offset = (page - 1) * per_page
      
      begin
        search_start = Time.utc
        results = shard_repo.search(query, offset, per_page)
        total = shard_repo.count_search(query)
        search_duration = (Time.utc - search_start).total_seconds
        Metrics::SEARCH_DURATION.observe(search_duration)
        
        {
          query: query,
          results: results.map(&.to_json),
          total: total,
          page: page,
          per_page: per_page,
          pages: (total / per_page.to_f).ceil.to_i
        }.to_json
      rescue ex
        env.response.status_code = 500
        {error: "Search error", message: ex.message}.to_json
      end
    end
  end
  
  # Shard submission endpoint
  post "/api/v1/shards" do |env|
    env.response.content_type = "application/json"
    
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