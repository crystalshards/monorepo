require "kemal"
require "kemal-session"
require "pg"
require "redis"
require "jwt"
require "dotenv"
require "json"

# Load environment variables
Dotenv.load

module CrystalShardsAdmin
  VERSION = "0.1.0"
  
  # WebSocket connection management
  WEBSOCKET_CONNECTIONS = Set(HTTP::WebSocket).new
  
  # Notification types
  enum NotificationType
    NewShard
    ShardApproved
    ShardRejected
    DocBuildStarted
    DocBuildCompleted
    DocBuildFailed
    NewJobPosting
    JobToggled
    SystemAlert
  end
  
  # Configuration
  DATABASE_URL_REGISTRY = ENV["DATABASE_URL_REGISTRY"]? || "postgres://postgres:password@localhost/crystalshards_development"
  DATABASE_URL_DOCS = ENV["DATABASE_URL_DOCS"]? || "postgres://postgres:password@localhost/crystaldocs_development"
  DATABASE_URL_GIGS = ENV["DATABASE_URL_GIGS"]? || "postgres://postgres:password@localhost/crystalgigs_development"
  REDIS_URL = ENV["REDIS_URL"]? || "redis://localhost:6379"
  JWT_SECRET = ENV["JWT_SECRET"]? || "admin_super_secret_key_change_me"
  ADMIN_USERNAME = ENV["ADMIN_USERNAME"]? || "admin"
  ADMIN_PASSWORD = ENV["ADMIN_PASSWORD"]? || "admin123"
  
  # Initialize database connections
  REGISTRY_DB = PG.connect(DATABASE_URL_REGISTRY)
  DOCS_DB = PG.connect(DATABASE_URL_DOCS)
  GIGS_DB = PG.connect(DATABASE_URL_GIGS)
  REDIS = Redis.new(url: REDIS_URL)
  
  # Authentication middleware
  class AuthHandler < Kemal::Handler
    def call(env)
      # Skip auth for login page and static assets
      if env.request.path == "/login" || env.request.path.starts_with?("/assets")
        call_next(env)
        return
      end
      
      token = env.session.string?("admin_token")
      unless token && valid_token?(token)
        env.redirect "/login"
        return
      end
      
      call_next(env)
    end
    
    private def valid_token?(token : String) : Bool
      CrystalShardsAdmin.valid_token?(token)
    end
  end
  
  # Enable sessions
  Kemal::Session.config do |config|
    config.secret = JWT_SECRET
  end
  
  add_handler AuthHandler.new
  
  # WebSocket notification broadcasting
  def self.broadcast_notification(type : NotificationType, data : Hash(String, JSON::Any))
    message = {
      type: type.to_s.underscore,
      timestamp: Time.utc.to_rfc3339,
      data: data
    }.to_json
    
    WEBSOCKET_CONNECTIONS.each do |ws|
      begin
        ws.send(message)
      rescue
        # Remove dead connections
        WEBSOCKET_CONNECTIONS.delete(ws)
      end
    end
  end
  
  def self.get_live_stats
    shard_stats = get_shard_stats
    docs_stats = get_docs_stats
    gigs_stats = get_gigs_stats
    
    {
      shards: shard_stats,
      docs: docs_stats,
      gigs: gigs_stats,
      timestamp: Time.utc.to_rfc3339
    }
  end
  
  # Helper methods (defined first)
  def self.get_shard_stats
    result = REGISTRY_DB.query_one("
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE published = true) as published,
        COUNT(*) FILTER (WHERE published = false) as pending
      FROM shards
    ", as: {Int64, Int64, Int64})
    
    {
      total: result[0],
      published: result[1],
      pending: result[2]
    }
  rescue
    {total: 0_i64, published: 0_i64, pending: 0_i64}
  end
  
  def self.get_docs_stats
    result = DOCS_DB.query_one("
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status = 'completed') as completed,
        COUNT(*) FILTER (WHERE status = 'building') as building
      FROM documentation
    ", as: {Int64, Int64, Int64})
    
    {
      total: result[0],
      completed: result[1],
      building: result[2]
    }
  rescue
    {total: 0_i64, completed: 0_i64, building: 0_i64}
  end
  
  def self.get_gigs_stats
    result = GIGS_DB.query_one("
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE active = true) as active,
        SUM(salary_max) as total_value
      FROM job_postings 
      WHERE created_at > NOW() - INTERVAL '30 days'
    ", as: {Int64, Int64, PG::Numeric?})
    
    {
      total: result[0],
      active: result[1],
      total_value: (result[2]?.try(&.to_f) || 0.0).to_i64
    }
  rescue
    {total: 0_i64, active: 0_i64, total_value: 0_i64}
  end
  
  def self.get_shards_for_review(status, offset, per_page)
    query = case status
            when "pending"
              "SELECT id, name, description, github_url, stars, published, created_at FROM shards WHERE published = false ORDER BY created_at DESC LIMIT $1 OFFSET $2"
            when "published"
              "SELECT id, name, description, github_url, stars, published, created_at FROM shards WHERE published = true ORDER BY updated_at DESC LIMIT $1 OFFSET $2"
            else
              "SELECT id, name, description, github_url, stars, published, created_at FROM shards ORDER BY created_at DESC LIMIT $1 OFFSET $2"
            end
    
    result = Array(Hash(Symbol, Int32 | String | String? | Bool | Time)).new
    REGISTRY_DB.query(query, per_page, offset) do |rs|
      rs.each do
        shard = Hash(Symbol, Int32 | String | String? | Bool | Time).new
        shard[:id] = rs.read(Int32)
        shard[:name] = rs.read(String)
        shard[:description] = rs.read(String?)
        shard[:github_url] = rs.read(String)
        shard[:stars] = rs.read(Int32)
        shard[:published] = rs.read(Bool)
        shard[:created_at] = rs.read(Time)
        result << shard
      end
    end
    result
  rescue
    Array(Hash(Symbol, Int32 | String | String? | Bool | Time)).new
  end
  
  def self.count_shards_for_review(status)
    query = case status
            when "pending"
              "SELECT COUNT(*) FROM shards WHERE published = false"
            when "published"
              "SELECT COUNT(*) FROM shards WHERE published = true"
            else
              "SELECT COUNT(*) FROM shards"
            end
    
    REGISTRY_DB.query_one(query, as: Int64)
  rescue
    0_i64
  end
  
  def self.approve_shard(shard_id)
    # Get shard info before update
    shard = REGISTRY_DB.query_one("SELECT name, description FROM shards WHERE id = $1", shard_id, as: {String, String?})
    
    REGISTRY_DB.exec("UPDATE shards SET published = true, updated_at = NOW() WHERE id = $1", shard_id)
    
    # Broadcast notification
    broadcast_notification(NotificationType::ShardApproved, {
      "shard_id" => JSON::Any.new(shard_id.to_i64),
      "name" => JSON::Any.new(shard[0]),
      "description" => JSON::Any.new(shard[1] || "")
    })
  rescue
    # Log error
  end
  
  def self.reject_shard(shard_id, reason)
    # Get shard info before update
    shard = REGISTRY_DB.query_one("SELECT name, description FROM shards WHERE id = $1", shard_id, as: {String, String?})
    
    REGISTRY_DB.exec("UPDATE shards SET published = false, rejection_reason = $2, updated_at = NOW() WHERE id = $1", shard_id, reason)
    
    # Broadcast notification
    broadcast_notification(NotificationType::ShardRejected, {
      "shard_id" => JSON::Any.new(shard_id.to_i64),
      "name" => JSON::Any.new(shard[0]),
      "reason" => JSON::Any.new(reason || "Quality issues")
    })
  rescue
    # Log error
  end
  
  def self.get_job_postings(offset, per_page)
    result = Array(Hash(Symbol, Int32 | Int32? | String | String? | Bool | Time)).new
    GIGS_DB.query("
      SELECT id, company, title, location, salary_min, salary_max, active, created_at 
      FROM job_postings 
      ORDER BY created_at DESC 
      LIMIT $1 OFFSET $2
    ", per_page, offset) do |rs|
      rs.each do
        job = Hash(Symbol, Int32 | Int32? | String | String? | Bool | Time).new
        job[:id] = rs.read(Int32)
        job[:company] = rs.read(String)
        job[:title] = rs.read(String)
        job[:location] = rs.read(String?)
        job[:salary_min] = rs.read(Int32?)
        job[:salary_max] = rs.read(Int32?)
        job[:active] = rs.read(Bool)
        job[:created_at] = rs.read(Time)
        result << job
      end
    end
    result
  rescue
    Array(Hash(Symbol, Int32 | Int32? | String | String? | Bool | Time)).new
  end
  
  def self.count_job_postings
    GIGS_DB.query_one("SELECT COUNT(*) FROM job_postings", as: Int64)
  rescue
    0_i64
  end
  
  def self.toggle_job_status(job_id)
    # Get job info before and after update
    job_before = GIGS_DB.query_one("SELECT company, title, active FROM job_postings WHERE id = $1", job_id, as: {String, String, Bool})
    
    GIGS_DB.exec("UPDATE job_postings SET active = NOT active WHERE id = $1", job_id)
    
    new_status = !job_before[2]
    
    # Broadcast notification
    broadcast_notification(NotificationType::JobToggled, {
      "job_id" => JSON::Any.new(job_id.to_i64),
      "company" => JSON::Any.new(job_before[0]),
      "title" => JSON::Any.new(job_before[1]),
      "new_status" => JSON::Any.new(new_status ? "active" : "inactive")
    })
  rescue
    # Log error
  end
  
  def self.get_recent_builds
    result = Array(Hash(Symbol, String | String? | Time)).new
    DOCS_DB.query("
      SELECT shard_name, version, status, created_at, build_logs
      FROM documentation 
      ORDER BY created_at DESC 
      LIMIT 50
    ") do |rs|
      rs.each do
        build = Hash(Symbol, String | String? | Time).new
        build[:shard_name] = rs.read(String)
        build[:version] = rs.read(String)
        build[:status] = rs.read(String)
        build[:created_at] = rs.read(Time)
        build[:build_logs] = rs.read(String?)
        result << build
      end
    end
    result
  rescue
    Array(Hash(Symbol, String | String? | Time)).new
  end
  
  # WebSocket endpoint for real-time notifications
  ws "/live" do |socket, context|
    # Add connection authentication check
    token = context.session.string?("admin_token")
    unless token && valid_token?(token)
      socket.close(code: 1008, message: "Authentication required")
      next
    end
    
    # Add connection to set
    WEBSOCKET_CONNECTIONS << socket
    
    # Send initial stats
    initial_data = get_live_stats
    socket.send({
      type: "initial_stats",
      timestamp: Time.utc.to_rfc3339,
      data: initial_data
    }.to_json)
    
    # Handle disconnection
    socket.on_close do
      WEBSOCKET_CONNECTIONS.delete(socket)
    end
    
    # Keep connection alive with periodic stats updates
    spawn do
      loop do
        sleep 10.seconds
        if WEBSOCKET_CONNECTIONS.includes?(socket)
          begin
            stats_data = get_live_stats
            socket.send({
              type: "stats_update",
              timestamp: Time.utc.to_rfc3339,
              data: stats_data
            }.to_json)
          rescue
            WEBSOCKET_CONNECTIONS.delete(socket)
            break
          end
        else
          break
        end
      end
    end
  end
  
  # Live stats API endpoint
  get "/api/stats" do |env|
    env.response.content_type = "application/json"
    get_live_stats.to_json
  end
  
  # Health check endpoint (no auth required)
  get "/health" do |env|
    env.response.content_type = "application/json"
    {
      status: "ok",
      version: VERSION,
      timestamp: Time.utc.to_s,
      active_connections: WEBSOCKET_CONNECTIONS.size
    }.to_json
  end
  
  # Helper method for token validation (must be defined before use)
  def self.valid_token?(token : String) : Bool
    JWT.decode(token, JWT_SECRET, JWT::Algorithm::HS256)
    true
  rescue JWT::DecodeError
    false
  end
  
  # Login page
  get "/login" do |env|
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>CrystalShards Admin Login</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                height: 100vh;
                margin: 0;
                display: flex;
                align-items: center;
                justify-content: center;
            }
            .login-container {
                background: white;
                padding: 2rem;
                border-radius: 10px;
                box-shadow: 0 10px 30px rgba(0,0,0,0.3);
                width: 100%;
                max-width: 400px;
            }
            .logo {
                text-align: center;
                color: #333;
                margin-bottom: 2rem;
            }
            .form-group {
                margin-bottom: 1rem;
            }
            label {
                display: block;
                margin-bottom: 0.5rem;
                font-weight: 500;
                color: #333;
            }
            input[type="text"], input[type="password"] {
                width: 100%;
                padding: 0.75rem;
                border: 1px solid #ddd;
                border-radius: 5px;
                font-size: 1rem;
                box-sizing: border-box;
            }
            button {
                width: 100%;
                padding: 0.75rem;
                background: #667eea;
                color: white;
                border: none;
                border-radius: 5px;
                font-size: 1rem;
                cursor: pointer;
                transition: background-color 0.2s;
            }
            button:hover {
                background: #5a6fd8;
            }
            .error {
                color: #e74c3c;
                margin-bottom: 1rem;
                text-align: center;
            }
        </style>
    </head>
    <body>
        <div class="login-container">
            <div class="logo">
                <h1>🔮 CrystalShards</h1>
                <p>Admin Interface</p>
            </div>
            #{env.params.query["error"]? ? "<div class='error'>Invalid credentials</div>" : ""}
            <form action="/login" method="POST">
                <div class="form-group">
                    <label for="username">Username</label>
                    <input type="text" id="username" name="username" required>
                </div>
                <div class="form-group">
                    <label for="password">Password</label>
                    <input type="password" id="password" name="password" required>
                </div>
                <button type="submit">Login</button>
            </form>
        </div>
    </body>
    </html>
    HTML
  end
  
  # Login handler
  post "/login" do |env|
    username = env.params.body["username"]?
    password = env.params.body["password"]?
    
    if username == ADMIN_USERNAME && password == ADMIN_PASSWORD
      # Create JWT token
      payload = {
        "sub" => username,
        "exp" => (Time.utc + 8.hours).to_unix,
        "iat" => Time.utc.to_unix,
        "role" => "admin"
      }
      
      token = JWT.encode(payload, JWT_SECRET, JWT::Algorithm::HS256)
      env.session.string("admin_token", token)
      env.redirect "/"
    else
      env.redirect "/login?error=1"
    end
  end
  
  # Logout
  get "/logout" do |env|
    env.session.destroy
    env.redirect "/login"
  end
  
  # Admin Dashboard
  get "/" do |env|
    # Get statistics from all databases
    shard_stats = CrystalShardsAdmin.get_shard_stats
    docs_stats = CrystalShardsAdmin.get_docs_stats
    gigs_stats = CrystalShardsAdmin.get_gigs_stats
    
    CrystalShardsAdmin.render_dashboard(shard_stats, docs_stats, gigs_stats)
  end
  
  # Shard management
  get "/shards" do |env|
    page = env.params.query["page"]?.try(&.to_i) || 1
    per_page = 20
    offset = (page - 1) * per_page
    status = env.params.query["status"]? || "all"
    
    shards = CrystalShardsAdmin.get_shards_for_review(status, offset, per_page)
    total = CrystalShardsAdmin.count_shards_for_review(status)
    
    CrystalShardsAdmin.render_shards_page(shards, page, per_page, total, status)
  end
  
  # Approve/reject shard
  post "/shards/:id/approve" do |env|
    shard_id = env.params.url["id"].to_i
    action = env.params.body["action"]?
    
    if action == "approve"
      CrystalShardsAdmin.approve_shard(shard_id)
    elsif action == "reject"
      CrystalShardsAdmin.reject_shard(shard_id, env.params.body["reason"]?)
    end
    
    env.redirect "/shards"
  end
  
  # Job postings management
  get "/jobs" do |env|
    page = env.params.query["page"]?.try(&.to_i) || 1
    per_page = 20
    offset = (page - 1) * per_page
    
    jobs = CrystalShardsAdmin.get_job_postings(offset, per_page)
    total = CrystalShardsAdmin.count_job_postings
    
    CrystalShardsAdmin.render_jobs_page(jobs, page, per_page, total)
  end
  
  # Job posting actions
  post "/jobs/:id/toggle" do |env|
    job_id = env.params.url["id"].to_i
    CrystalShardsAdmin.toggle_job_status(job_id)
    env.redirect "/jobs"
  end
  
  # Documentation build management
  get "/docs" do |env|
    builds = CrystalShardsAdmin.get_recent_builds
    CrystalShardsAdmin.render_docs_page(builds)
  end
  
  # Render methods
  def self.render_dashboard(shard_stats, docs_stats, gigs_stats)
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>CrystalShards Admin Dashboard</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: #f8f9fa;
                color: #333;
            }
            .navbar {
                background: #667eea;
                color: white;
                padding: 1rem 2rem;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }
            .navbar h1 { font-size: 1.5rem; }
            .nav-links { display: flex; gap: 2rem; }
            .nav-links a { color: white; text-decoration: none; }
            .nav-links a:hover { opacity: 0.8; }
            .container { padding: 2rem; max-width: 1200px; margin: 0 auto; }
            .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 2rem; margin-bottom: 3rem; }
            .stat-card {
                background: white;
                padding: 2rem;
                border-radius: 10px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            .stat-card h3 { color: #667eea; margin-bottom: 1rem; }
            .stat-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1rem; }
            .stat-item { text-align: center; }
            .stat-number { font-size: 2rem; font-weight: bold; color: #333; transition: color 0.3s; }
            .stat-number.updated { color: #28a745; }
            .stat-label { color: #666; font-size: 0.9rem; }
            .notification-toast {
                position: fixed;
                top: 20px;
                right: 20px;
                background: #28a745;
                color: white;
                padding: 1rem;
                border-radius: 5px;
                box-shadow: 0 4px 12px rgba(0,0,0,0.3);
                transform: translateX(300px);
                transition: transform 0.3s;
                z-index: 1000;
                min-width: 300px;
            }
            .notification-toast.show { transform: translateX(0); }
            .notification-toast.error { background: #dc3545; }
            .notification-toast.warning { background: #ffc107; color: #212529; }
            .connection-status {
                position: fixed;
                bottom: 20px;
                right: 20px;
                padding: 0.5rem 1rem;
                border-radius: 20px;
                font-size: 0.8rem;
                font-weight: 500;
            }
            .connection-status.connected { background: #d1ecf1; color: #0c5460; }
            .connection-status.disconnected { background: #f8d7da; color: #721c24; }
            .connection-status.reconnecting { background: #fff3cd; color: #856404; }
        </style>
    </head>
    <body>
        <nav class="navbar">
            <h1>🔮 CrystalShards Admin</h1>
            <div class="nav-links">
                <a href="/">Dashboard</a>
                <a href="/shards">Shards</a>
                <a href="/jobs">Jobs</a>
                <a href="/docs">Docs</a>
                <a href="/logout">Logout</a>
            </div>
        </nav>
        
        <div class="container">
            <h2>Platform Overview</h2>
            
            <div class="stats-grid">
                <div class="stat-card">
                    <h3>📦 Shards Registry</h3>
                    <div class="stat-grid">
                        <div class="stat-item">
                            <div id="shards-total" class="stat-number">#{shard_stats[:total]}</div>
                            <div class="stat-label">Total Shards</div>
                        </div>
                        <div class="stat-item">
                            <div id="shards-published" class="stat-number">#{shard_stats[:published]}</div>
                            <div class="stat-label">Published</div>
                        </div>
                        <div class="stat-item">
                            <div id="shards-pending" class="stat-number">#{shard_stats[:pending]}</div>
                            <div class="stat-label">Pending Review</div>
                        </div>
                    </div>
                </div>
                
                <div class="stat-card">
                    <h3>📚 Documentation</h3>
                    <div class="stat-grid">
                        <div class="stat-item">
                            <div id="docs-total" class="stat-number">#{docs_stats[:total]}</div>
                            <div class="stat-label">Total Docs</div>
                        </div>
                        <div class="stat-item">
                            <div id="docs-completed" class="stat-number">#{docs_stats[:completed]}</div>
                            <div class="stat-label">Completed</div>
                        </div>
                        <div class="stat-item">
                            <div id="docs-building" class="stat-number">#{docs_stats[:building]}</div>
                            <div class="stat-label">Building</div>
                        </div>
                    </div>
                </div>
                
                <div class="stat-card">
                    <h3>💼 Job Board</h3>
                    <div class="stat-grid">
                        <div class="stat-item">
                            <div id="gigs-total" class="stat-number">#{gigs_stats[:total]}</div>
                            <div class="stat-label">Total Jobs (30d)</div>
                        </div>
                        <div class="stat-item">
                            <div id="gigs-active" class="stat-number">#{gigs_stats[:active]}</div>
                            <div class="stat-label">Active</div>
                        </div>
                        <div class="stat-item">
                            <div id="gigs-value" class="stat-number">$#{(gigs_stats[:total_value] / 1000).to_i}k</div>
                            <div class="stat-label">Total Value</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Notification container -->
        <div id="notification-container"></div>
        
        <!-- Connection status indicator -->
        <div id="connection-status" class="connection-status disconnected">Connecting...</div>
        
        <script>
            let ws = null;
            let reconnectTimeout = null;
            let isConnected = false;
            
            function connect() {
                const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
                const wsUrl = protocol + '//' + window.location.host + '/live';
                
                ws = new WebSocket(wsUrl);
                
                ws.onopen = function() {
                    isConnected = true;
                    updateConnectionStatus('connected', '🟢 Live Updates Active');
                    console.log('WebSocket connected');
                };
                
                ws.onmessage = function(event) {
                    try {
                        const message = JSON.parse(event.data);
                        handleMessage(message);
                    } catch (e) {
                        console.error('Error parsing WebSocket message:', e);
                    }
                };
                
                ws.onclose = function() {
                    isConnected = false;
                    updateConnectionStatus('disconnected', '🔴 Disconnected');
                    console.log('WebSocket disconnected, attempting to reconnect...');
                    
                    // Attempt to reconnect after 3 seconds
                    reconnectTimeout = setTimeout(function() {
                        updateConnectionStatus('reconnecting', '🟡 Reconnecting...');
                        connect();
                    }, 3000);
                };
                
                ws.onerror = function(error) {
                    console.error('WebSocket error:', error);
                };
            }
            
            function handleMessage(message) {
                console.log('Received message:', message);
                
                switch(message.type) {
                    case 'initial_stats':
                    case 'stats_update':
                        updateStats(message.data);
                        break;
                    case 'shard_approved':
                        showNotification('Shard Approved', 
                            `✅ "${message.data.name}" has been approved and published!`, 'success');
                        break;
                    case 'shard_rejected':
                        showNotification('Shard Rejected', 
                            `❌ "${message.data.name}" was rejected: ${message.data.reason}`, 'error');
                        break;
                    case 'job_toggled':
                        showNotification('Job Status Changed', 
                            `💼 "${message.data.title}" at ${message.data.company} is now ${message.data.new_status}`, 'warning');
                        break;
                    case 'new_shard':
                        showNotification('New Shard Submission', 
                            `📦 New shard "${message.data.name}" submitted for review`, 'success');
                        break;
                    case 'doc_build_completed':
                        showNotification('Documentation Built', 
                            `📚 Documentation for "${message.data.shard_name}" v${message.data.version} completed`, 'success');
                        break;
                    case 'doc_build_failed':
                        showNotification('Documentation Build Failed', 
                            `❌ Documentation build failed for "${message.data.shard_name}" v${message.data.version}`, 'error');
                        break;
                }
            }
            
            function updateStats(stats) {
                // Update shard stats
                if (stats.shards) {
                    updateStatNumber('shards-total', stats.shards.total);
                    updateStatNumber('shards-published', stats.shards.published);
                    updateStatNumber('shards-pending', stats.shards.pending);
                }
                
                // Update docs stats
                if (stats.docs) {
                    updateStatNumber('docs-total', stats.docs.total);
                    updateStatNumber('docs-completed', stats.docs.completed);
                    updateStatNumber('docs-building', stats.docs.building);
                }
                
                // Update gigs stats
                if (stats.gigs) {
                    updateStatNumber('gigs-total', stats.gigs.total);
                    updateStatNumber('gigs-active', stats.gigs.active);
                    updateStatNumber('gigs-value', '$' + Math.floor(stats.gigs.total_value / 1000) + 'k');
                }
            }
            
            function updateStatNumber(id, value) {
                const element = document.getElementById(id);
                if (element && element.textContent != value) {
                    element.textContent = value;
                    element.classList.add('updated');
                    setTimeout(() => element.classList.remove('updated'), 2000);
                }
            }
            
            function updateConnectionStatus(status, text) {
                const statusEl = document.getElementById('connection-status');
                statusEl.className = 'connection-status ' + status;
                statusEl.textContent = text;
            }
            
            function showNotification(title, message, type = 'success') {
                const notification = document.createElement('div');
                notification.className = 'notification-toast ' + type;
                notification.innerHTML = `
                    <div style="font-weight: bold; margin-bottom: 0.5rem;">${title}</div>
                    <div>${message}</div>
                `;
                
                document.getElementById('notification-container').appendChild(notification);
                
                // Show notification
                setTimeout(() => notification.classList.add('show'), 100);
                
                // Auto-hide after 5 seconds
                setTimeout(() => {
                    notification.classList.remove('show');
                    setTimeout(() => notification.remove(), 300);
                }, 5000);
            }
            
            // Connect when page loads
            connect();
            
            // Cleanup on page unload
            window.addEventListener('beforeunload', function() {
                if (reconnectTimeout) clearTimeout(reconnectTimeout);
                if (ws) ws.close();
            });
        </script>
    </body>
    </html>
    HTML
  end
  
  def self.render_shards_page(shards, page, per_page, total, status)
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>Shard Management - CrystalShards Admin</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: #f8f9fa;
                color: #333;
            }
            .navbar {
                background: #667eea;
                color: white;
                padding: 1rem 2rem;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }
            .navbar h1 { font-size: 1.5rem; }
            .nav-links { display: flex; gap: 2rem; }
            .nav-links a { color: white; text-decoration: none; }
            .nav-links a:hover { opacity: 0.8; }
            .container { padding: 2rem; max-width: 1200px; margin: 0 auto; }
            .filters { display: flex; gap: 1rem; margin-bottom: 2rem; }
            .filter-btn {
                padding: 0.5rem 1rem;
                border: 1px solid #ddd;
                background: white;
                color: #333;
                text-decoration: none;
                border-radius: 5px;
            }
            .filter-btn.active { background: #667eea; color: white; }
            .shard-list { background: white; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .shard-item {
                padding: 1.5rem;
                border-bottom: 1px solid #eee;
                display: grid;
                grid-template-columns: 1fr auto auto;
                gap: 1rem;
                align-items: center;
            }
            .shard-info h4 { color: #667eea; margin-bottom: 0.5rem; }
            .shard-info p { color: #666; font-size: 0.9rem; margin-bottom: 0.5rem; }
            .shard-meta { display: flex; gap: 1rem; font-size: 0.8rem; color: #999; }
            .status-badge {
                padding: 0.25rem 0.5rem;
                border-radius: 3px;
                font-size: 0.8rem;
                font-weight: 500;
            }
            .status-pending { background: #fff3cd; color: #856404; }
            .status-published { background: #d1ecf1; color: #0c5460; }
            .actions { display: flex; gap: 0.5rem; }
            .btn {
                padding: 0.5rem 1rem;
                border: none;
                border-radius: 5px;
                cursor: pointer;
                font-size: 0.9rem;
            }
            .btn-approve { background: #28a745; color: white; }
            .btn-reject { background: #dc3545; color: white; }
            .pagination {
                display: flex;
                justify-content: center;
                gap: 0.5rem;
                margin-top: 2rem;
            }
            .page-link {
                padding: 0.5rem 1rem;
                border: 1px solid #ddd;
                background: white;
                color: #667eea;
                text-decoration: none;
                border-radius: 5px;
            }
            .page-link.active { background: #667eea; color: white; }
        </style>
    </head>
    <body>
        <nav class="navbar">
            <h1>🔮 CrystalShards Admin</h1>
            <div class="nav-links">
                <a href="/">Dashboard</a>
                <a href="/shards">Shards</a>
                <a href="/jobs">Jobs</a>
                <a href="/docs">Docs</a>
                <a href="/logout">Logout</a>
            </div>
        </nav>
        
        <div class="container">
            <h2>Shard Management</h2>
            
            <div class="filters">
                <a href="/shards?status=all" class="filter-btn #{status == "all" ? "active" : ""}">All (#{total})</a>
                <a href="/shards?status=pending" class="filter-btn #{status == "pending" ? "active" : ""}">Pending Review</a>
                <a href="/shards?status=published" class="filter-btn #{status == "published" ? "active" : ""}">Published</a>
            </div>
            
            <div class="shard-list">
                #{shards.map { |shard|
                  actions_html = unless shard[:published].as(Bool)
                    %(<div class="actions">
                        <form action="/shards/#{shard[:id]}/approve" method="POST" style="display: inline;">
                            <input type="hidden" name="action" value="approve">
                            <button type="submit" class="btn btn-approve">Approve</button>
                        </form>
                        <form action="/shards/#{shard[:id]}/approve" method="POST" style="display: inline;">
                            <input type="hidden" name="action" value="reject">
                            <input type="hidden" name="reason" value="Quality issues">
                            <button type="submit" class="btn btn-reject">Reject</button>
                        </form>
                    </div>)
                  else
                    "<div></div>"
                  end
                  
                  %(<div class="shard-item">
                      <div class="shard-info">
                          <h4>#{shard[:name]}</h4>
                          <p>#{shard[:description] || "No description available"}</p>
                          <div class="shard-meta">
                              <span>⭐ #{shard[:stars]} stars</span>
                              <span>📅 #{shard[:created_at].as(Time).to_s("%Y-%m-%d")}</span>
                              <span>🔗 <a href="#{shard[:github_url]}" target="_blank">GitHub</a></span>
                          </div>
                      </div>
                      <div>
                          <span class="status-badge #{shard[:published].as(Bool) ? "status-published" : "status-pending"}">
                              #{shard[:published].as(Bool) ? "Published" : "Pending"}
                          </span>
                      </div>
                      #{actions_html}
                  </div>)
                }.join}
            </div>
            
            #{if total > per_page
              pages = (total / per_page.to_f).ceil.to_i
              pagination_links = (1..pages).map { |p|
                if p == page
                  %(<span class="page-link active">#{p}</span>)
                else
                  %(<a href="/shards?page=#{p}&status=#{status}" class="page-link">#{p}</a>)
                end
              }.join
              %(<div class="pagination">#{pagination_links}</div>)
            else
              ""
            end}
        </div>
    </body>
    </html>
    HTML
  end
  
  def self.render_jobs_page(jobs, page, per_page, total)
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>Job Management - CrystalShards Admin</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: #f8f9fa;
                color: #333;
            }
            .navbar {
                background: #667eea;
                color: white;
                padding: 1rem 2rem;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }
            .navbar h1 { font-size: 1.5rem; }
            .nav-links { display: flex; gap: 2rem; }
            .nav-links a { color: white; text-decoration: none; }
            .nav-links a:hover { opacity: 0.8; }
            .container { padding: 2rem; max-width: 1200px; margin: 0 auto; }
            .job-list { background: white; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .job-item {
                padding: 1.5rem;
                border-bottom: 1px solid #eee;
                display: grid;
                grid-template-columns: 1fr auto auto;
                gap: 1rem;
                align-items: center;
            }
            .job-info h4 { color: #667eea; margin-bottom: 0.5rem; }
            .job-info p { color: #666; font-size: 0.9rem; margin-bottom: 0.5rem; }
            .job-meta { display: flex; gap: 1rem; font-size: 0.8rem; color: #999; }
            .salary { font-weight: bold; color: #28a745; }
            .status-badge {
                padding: 0.25rem 0.5rem;
                border-radius: 3px;
                font-size: 0.8rem;
                font-weight: 500;
            }
            .status-active { background: #d1ecf1; color: #0c5460; }
            .status-inactive { background: #f8d7da; color: #721c24; }
            .btn {
                padding: 0.5rem 1rem;
                border: none;
                border-radius: 5px;
                cursor: pointer;
                font-size: 0.9rem;
                text-decoration: none;
                display: inline-block;
            }
            .btn-toggle { background: #ffc107; color: #212529; }
            .pagination {
                display: flex;
                justify-content: center;
                gap: 0.5rem;
                margin-top: 2rem;
            }
            .page-link {
                padding: 0.5rem 1rem;
                border: 1px solid #ddd;
                background: white;
                color: #667eea;
                text-decoration: none;
                border-radius: 5px;
            }
            .page-link.active { background: #667eea; color: white; }
            .stats-summary {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 1rem;
                margin-bottom: 2rem;
            }
            .stat-box {
                background: white;
                padding: 1.5rem;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                text-align: center;
            }
            .stat-number { font-size: 2rem; font-weight: bold; color: #667eea; }
            .stat-label { color: #666; margin-top: 0.5rem; }
        </style>
    </head>
    <body>
        <nav class="navbar">
            <h1>🔮 CrystalShards Admin</h1>
            <div class="nav-links">
                <a href="/">Dashboard</a>
                <a href="/shards">Shards</a>
                <a href="/jobs">Jobs</a>
                <a href="/docs">Docs</a>
                <a href="/logout">Logout</a>
            </div>
        </nav>
        
        <div class="container">
            <h2>Job Posting Management</h2>
            
            <div class="stats-summary">
                <div class="stat-box">
                    <div class="stat-number">#{total}</div>
                    <div class="stat-label">Total Jobs</div>
                </div>
                <div class="stat-box">
                    <div class="stat-number">#{jobs.count { |j| j[:active].as(Bool) }}</div>
                    <div class="stat-label">Active Jobs</div>
                </div>
                <div class="stat-box">
                    <div class="stat-number">#{jobs.count { |j| !j[:active].as(Bool) }}</div>
                    <div class="stat-label">Inactive Jobs</div>
                </div>
            </div>
            
            <div class="job-list">
                #{jobs.map { |job|
                  salary_min = job[:salary_min].as(Int32?)
                  salary_max = job[:salary_max].as(Int32?)
                  salary_range = if salary_min && salary_max
                                   if salary_min == salary_max
                                     "$#{(salary_max / 1000).to_i}k"
                                   else
                                     "$#{(salary_min / 1000).to_i}k - $#{(salary_max / 1000).to_i}k"
                                   end
                                 elsif salary_max
                                   "Up to $#{(salary_max / 1000).to_i}k"
                                 else
                                   "Salary not specified"
                                 end
                  
                  %(<div class="job-item">
                      <div class="job-info">
                          <h4>#{job[:title]} at #{job[:company]}</h4>
                          <p><strong>Location:</strong> #{job[:location] || "Remote/Unspecified"}</p>
                          <div class="job-meta">
                              <span class="salary">💰 #{salary_range}</span>
                              <span>📅 #{job[:created_at].as(Time).to_s("%Y-%m-%d")}</span>
                          </div>
                      </div>
                      <div>
                          <span class="status-badge #{job[:active].as(Bool) ? "status-active" : "status-inactive"}">
                              #{job[:active].as(Bool) ? "Active" : "Inactive"}
                          </span>
                      </div>
                      <div class="actions">
                          <form action="/jobs/#{job[:id]}/toggle" method="POST" style="display: inline;">
                              <button type="submit" class="btn btn-toggle">
                                  #{job[:active].as(Bool) ? "Deactivate" : "Activate"}
                              </button>
                          </form>
                      </div>
                  </div>)
                }.join}
            </div>
            
            #{if total > per_page
              pages = (total / per_page.to_f).ceil.to_i
              pagination_links = (1..pages).map { |p|
                if p == page
                  %(<span class="page-link active">#{p}</span>)
                else
                  %(<a href="/jobs?page=#{p}" class="page-link">#{p}</a>)
                end
              }.join
              %(<div class="pagination">#{pagination_links}</div>)
            else
              ""
            end}
        </div>
    </body>
    </html>
    HTML
  end
  
  def self.render_docs_page(builds)
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>Documentation Management - CrystalShards Admin</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                background: #f8f9fa;
                color: #333;
            }
            .navbar {
                background: #667eea;
                color: white;
                padding: 1rem 2rem;
                display: flex;
                justify-content: space-between;
                align-items: center;
            }
            .navbar h1 { font-size: 1.5rem; }
            .nav-links { display: flex; gap: 2rem; }
            .nav-links a { color: white; text-decoration: none; }
            .nav-links a:hover { opacity: 0.8; }
            .container { padding: 2rem; max-width: 1200px; margin: 0 auto; }
            .build-list { background: white; border-radius: 10px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .build-item {
                padding: 1.5rem;
                border-bottom: 1px solid #eee;
                display: grid;
                grid-template-columns: 1fr auto;
                gap: 1rem;
                align-items: center;
            }
            .build-info h4 { color: #667eea; margin-bottom: 0.5rem; }
            .build-info p { color: #666; font-size: 0.9rem; margin-bottom: 0.5rem; }
            .build-meta { display: flex; gap: 1rem; font-size: 0.8rem; color: #999; }
            .status-badge {
                padding: 0.25rem 0.5rem;
                border-radius: 3px;
                font-size: 0.8rem;
                font-weight: 500;
            }
            .status-completed { background: #d1ecf1; color: #0c5460; }
            .status-building { background: #fff3cd; color: #856404; }
            .status-failed { background: #f8d7da; color: #721c24; }
            .stats-summary {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 1rem;
                margin-bottom: 2rem;
            }
            .stat-box {
                background: white;
                padding: 1.5rem;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                text-align: center;
            }
            .stat-number { font-size: 2rem; font-weight: bold; color: #667eea; }
            .stat-label { color: #666; margin-top: 0.5rem; }
            .build-logs {
                background: #f1f3f4;
                padding: 1rem;
                border-radius: 5px;
                margin-top: 0.5rem;
                font-family: monospace;
                font-size: 0.8rem;
                max-height: 100px;
                overflow-y: auto;
                white-space: pre-wrap;
            }
            .expandable { cursor: pointer; }
            .expandable:hover { background: #e9ecef; }
        </style>
    </head>
    <body>
        <nav class="navbar">
            <h1>🔮 CrystalShards Admin</h1>
            <div class="nav-links">
                <a href="/">Dashboard</a>
                <a href="/shards">Shards</a>
                <a href="/jobs">Jobs</a>
                <a href="/docs">Docs</a>
                <a href="/logout">Logout</a>
            </div>
        </nav>
        
        <div class="container">
            <h2>Documentation Build Management</h2>
            
            <div class="stats-summary">
                <div class="stat-box">
                    <div class="stat-number">#{builds.size}</div>
                    <div class="stat-label">Recent Builds</div>
                </div>
                <div class="stat-box">
                    <div class="stat-number">#{builds.count { |b| b[:status] == "completed" }}</div>
                    <div class="stat-label">Completed</div>
                </div>
                <div class="stat-box">
                    <div class="stat-number">#{builds.count { |b| b[:status] == "building" }}</div>
                    <div class="stat-label">Building</div>
                </div>
                <div class="stat-box">
                    <div class="stat-number">#{builds.count { |b| b[:status] == "failed" }}</div>
                    <div class="stat-label">Failed</div>
                </div>
            </div>
            
            <div class="build-list">
                #{builds.map { |build|
                  status_class = case build[:status]
                                when "completed"
                                  "status-completed"
                                when "building"
                                  "status-building"
                                else
                                  "status-failed"
                                end
                  
                  build_logs = build[:build_logs].as(String?)
                  logs_html = if build_logs && !build_logs.empty?
                    %(<div class="build-logs expandable" onclick="this.style.maxHeight = this.style.maxHeight === 'none' ? '100px' : 'none'">
                        #{build_logs}
                    </div>)
                  else
                    ""
                  end
                  
                  %(<div class="build-item">
                      <div class="build-info">
                          <h4>#{build[:shard_name]} v#{build[:version]}</h4>
                          <div class="build-meta">
                              <span>📅 #{build[:created_at].as(Time).to_s("%Y-%m-%d %H:%M")}</span>
                              <span>🔧 Build Status</span>
                          </div>
                          #{logs_html}
                      </div>
                      <div>
                          <span class="status-badge #{status_class}">
                              #{build[:status].as(String).capitalize}
                          </span>
                      </div>
                  </div>)
                }.join}
            </div>
            
            #{if builds.empty?
              %(<div style="text-align: center; padding: 3rem; color: #666;">
                  <h3>No recent builds found</h3>
                  <p>Documentation builds will appear here once they start.</p>
              </div>)
            else
              ""
            end}
        </div>
        
        <script>
            // Auto-refresh every 30 seconds to show live build status
            setTimeout(function() {
                window.location.reload();
            }, 30000);
        </script>
    </body>
    </html>
    HTML
  end
end

# Start the server
port = ENV["PORT"]?.try(&.to_i) || 4000
puts "Starting CrystalShards Admin Interface on port #{port}"
Kemal.run(port)