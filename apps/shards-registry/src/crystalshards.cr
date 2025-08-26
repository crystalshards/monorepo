require "kemal"
require "pg"
require "redis"
require "jwt"
require "cr-dotenv"

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
  
  # Health check endpoint
  get "/health" do |env|
    env.response.content_type = "application/json"
    {
      status: "ok",
      version: VERSION,
      timestamp: Time.utc.to_s
    }.to_json
  end
  
  # API root
  get "/api/v1" do |env|
    env.response.content_type = "application/json"
    {
      message: "CrystalShards API v1",
      version: VERSION,
      endpoints: {
        shards: "/api/v1/shards",
        search: "/api/v1/search",
        health: "/health"
      }
    }.to_json
  end
  
  # Shards listing endpoint
  get "/api/v1/shards" do |env|
    env.response.content_type = "application/json"
    
    # Placeholder - will implement with database queries
    {
      shards: [] of String,
      total: 0,
      page: 1,
      per_page: 20
    }.to_json
  end
  
  # Search endpoint
  get "/api/v1/search" do |env|
    env.response.content_type = "application/json"
    query = env.params.query["q"]? || ""
    
    # Placeholder - will implement with search functionality
    {
      query: query,
      results: [] of String,
      total: 0
    }.to_json
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