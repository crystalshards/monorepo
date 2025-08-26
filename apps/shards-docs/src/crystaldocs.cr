require "kemal"
require "pg"
require "redis"
require "markd"
require "cr-dotenv"

# Load environment variables
Dotenv.load

module CrystalDocs
  VERSION = "0.1.0"
  
  # Configuration
  DATABASE_URL = ENV["DATABASE_URL"]? || "postgres://postgres:password@localhost/crystaldocs_development"
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
  
  # Documentation root
  get "/" do |env|
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>CrystalDocs - Crystal Documentation Platform</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; }
        .header { text-align: center; margin-bottom: 40px; }
        .search { margin: 20px 0; }
        .search input { padding: 10px; width: 300px; border: 1px solid #ddd; border-radius: 4px; }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>CrystalDocs</h1>
        <p>Crystal Package Documentation Platform</p>
      </div>
      <div class="search">
        <form action="/search" method="get">
          <input type="text" name="q" placeholder="Search documentation..." />
          <button type="submit">Search</button>
        </form>
      </div>
      <div class="recent">
        <h3>Recent Documentation</h3>
        <p>No documentation available yet.</p>
      </div>
    </body>
    </html>
    HTML
  end
  
  # Package documentation viewer
  get "/docs/:package" do |env|
    package = env.params.url["package"]
    env.response.content_type = "text/html"
    
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>#{package} - CrystalDocs</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; }
        .sidebar { width: 250px; height: 100vh; background: #f8f9fa; padding: 20px; position: fixed; }
        .content { margin-left: 290px; padding: 20px; }
        .nav-item { padding: 5px 0; }
        .nav-item a { text-decoration: none; color: #333; }
        .nav-item a:hover { color: #007bff; }
      </style>
    </head>
    <body>
      <div class="sidebar">
        <h3>#{package}</h3>
        <div class="nav-item"><a href="#overview">Overview</a></div>
        <div class="nav-item"><a href="#installation">Installation</a></div>
        <div class="nav-item"><a href="#api">API Reference</a></div>
      </div>
      <div class="content">
        <h1>#{package}</h1>
        <p>Documentation for #{package} will be generated here.</p>
        <h2 id="overview">Overview</h2>
        <p>Package overview and description.</p>
        <h2 id="installation">Installation</h2>
        <pre><code>dependencies:
  #{package}:
    github: username/#{package}</code></pre>
        <h2 id="api">API Reference</h2>
        <p>API documentation will be generated from source code.</p>
      </div>
    </body>
    </html>
    HTML
  end
  
  # Search endpoint
  get "/search" do |env|
    query = env.params.query["q"]? || ""
    env.response.content_type = "text/html"
    
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Search: #{query} - CrystalDocs</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; }
        .search { margin: 20px 0; }
        .search input { padding: 10px; width: 300px; border: 1px solid #ddd; border-radius: 4px; }
        .results { margin-top: 20px; }
        .result { padding: 15px; border-bottom: 1px solid #eee; }
        .result h3 { margin: 0 0 10px 0; }
      </style>
    </head>
    <body>
      <h1>Search Results</h1>
      <div class="search">
        <form action="/search" method="get">
          <input type="text" name="q" value="#{query}" placeholder="Search documentation..." />
          <button type="submit">Search</button>
        </form>
      </div>
      <div class="results">
        <p>Search functionality will be implemented here.</p>
        <p>Query: "#{query}"</p>
      </div>
    </body>
    </html>
    HTML
  end
  
  # API endpoint for documentation data
  get "/api/v1/docs/:package" do |env|
    env.response.content_type = "application/json"
    package = env.params.url["package"]
    
    # Placeholder - will implement with actual doc generation
    {
      package: package,
      version: "latest",
      documentation: {
        readme: "",
        api: [] of String,
        examples: [] of String
      },
      generated_at: Time.utc.to_s
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
    env.response.content_type = "text/html"
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head><title>Not Found - CrystalDocs</title></head>
    <body style="font-family: sans-serif; text-align: center; margin-top: 100px;">
      <h1>404 - Page Not Found</h1>
      <p><a href="/">Back to Home</a></p>
    </body>
    </html>
    HTML
  end
end

# Start the server
port = ENV["PORT"]?.try(&.to_i) || 3001
puts "Starting CrystalDocs on port #{port}"
Kemal.run(port)