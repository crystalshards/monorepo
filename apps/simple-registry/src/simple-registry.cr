require "http/server"
require "json"

# Simple, minimal Crystal Shards Registry for initial deployment
# Focus: Get something deployed and web-accessible first
# Using HTTP::Server directly to avoid Kemal compatibility issues

def handle_request(context : HTTP::Server::Context)
  path = context.request.path
  
  case path
  when "/"
    context.response.content_type = "text/html"
    context.response.print <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Crystal Shards Registry</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; text-align: center; }
        .status { background: #e8f5e8; padding: 20px; border-radius: 4px; margin: 20px 0; }
        .api-links { margin: 30px 0; }
        .api-links a { display: inline-block; background: #007cba; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; margin: 5px; }
        .api-links a:hover { background: #005c8a; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>Crystal Shards Registry</h1>
        <div class="status">
          <strong>Status:</strong> ✅ Deployed and Running<br>
          <strong>Version:</strong> 1.0.0-minimal<br>
          <strong>Framework:</strong> HTTP::Server (Crystal stdlib)<br>
          <strong>Environment:</strong> #{ENV.fetch("ENV", "development")}
        </div>
        
        <h2>Available APIs</h2>
        <div class="api-links">
          <a href="/health">Health Check</a>
          <a href="/api/stats">Statistics</a>
          <a href="/api/shards">Shards List</a>
        </div>
        
        <p>This is a minimal deployment of the Crystal Shards Registry platform. 
        Full functionality will be added incrementally after confirming basic deployment works.</p>
        
        <p><strong>Next steps:</strong> Convert to Lucky framework and add database connectivity.</p>
      </div>
    </body>
    </html>
    HTML
    
  when "/health"
    context.response.content_type = "application/json"
    context.response.print({
      status: "healthy",
      service: "crystal-shards-registry",
      version: "1.0.0-minimal",
      timestamp: Time.utc.to_s,
      environment: ENV.fetch("ENV", "development"),
      framework: "HTTP::Server"
    }.to_json)
    
  when "/api/stats"
    context.response.content_type = "application/json"
    context.response.print({
      shards_count: 0,
      users_count: 0,
      total_downloads: 0,
      status: "minimal_deployment",
      message: "Statistics will be available once database is connected"
    }.to_json)
    
  when "/api/shards"
    context.response.content_type = "application/json"
    context.response.print({
      shards: [] of String,
      total: 0,
      message: "Shard data will be available once database is connected",
      api_version: "1.0.0-minimal"
    }.to_json)
    
  else
    context.response.status_code = 404
    context.response.content_type = "application/json"
    context.response.print({
      error: "Not Found",
      path: path,
      message: "Endpoint not available in minimal deployment"
    }.to_json)
  end
end

# Start the server
port = ENV.fetch("PORT", "3000").to_i

puts "Crystal Shards Registry (minimal) starting..."
puts "Framework: Crystal HTTP::Server (standard library)"
puts "Environment: #{ENV.fetch("ENV", "development")}"
puts "Port: #{port}"
puts "Visit: http://localhost:#{port}"

server = HTTP::Server.new do |context|
  begin
    handle_request(context)
  rescue ex
    context.response.status_code = 500
    context.response.content_type = "application/json"
    context.response.print({
      error: "Internal Server Error",
      message: ex.message
    }.to_json)
    STDERR.puts "Error handling request #{context.request.path}: #{ex}"
  end
end

server.bind_tcp port
server.listen