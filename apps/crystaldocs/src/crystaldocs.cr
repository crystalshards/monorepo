require "kemal"
require "pg"
require "redis"
require "markd"
require "dotenv"
require "./services/doc_build_service"
require "./services/doc_storage_service"
require "./services/doc_parser_service"
require "./repositories/documentation_repository"
require "./metrics"

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
  
  # Add metrics middleware
  add_handler Metrics::MetricsHandler.new
  
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
  
  # Package documentation viewer (redirects to latest version)
  get "/docs/:package" do |env|
    package = env.params.url["package"]
    
    # Redirect to latest version
    env.redirect("/docs/#{package}/latest")
  end
  
  # Search endpoint
  get "/search" do |env|
    query = env.params.query["q"]? || ""
    env.response.content_type = "text/html"
    
    # Perform search if query is provided
    results = [] of Hash(String, DB::Any)
    if !query.empty?
      results = DocumentationRepository.search(query, 20)
    end
    
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Search: #{query} - CrystalDocs</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 0; }
        .header { background: #007bff; color: white; padding: 20px; }
        .header h1 { margin: 0; }
        .header .search { margin-top: 15px; }
        .header input { padding: 10px; width: 400px; border: none; border-radius: 4px; }
        .header button { padding: 10px 20px; border: none; background: #0056b3; color: white; border-radius: 4px; margin-left: 10px; }
        .content { max-width: 1000px; margin: 0 auto; padding: 20px; }
        .results-info { margin: 20px 0; color: #666; }
        .result { padding: 20px; border-bottom: 1px solid #eee; }
        .result:hover { background: #f8f9fa; }
        .result h3 { margin: 0 0 10px 0; }
        .result h3 a { text-decoration: none; color: #007bff; }
        .result h3 a:hover { text-decoration: underline; }
        .result .meta { color: #666; font-size: 14px; margin-bottom: 5px; }
        .result .description { color: #333; line-height: 1.4; }
        .no-results { text-align: center; padding: 60px 20px; color: #666; }
        .suggestions { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .suggestions h4 { margin-top: 0; }
        @media (max-width: 768px) {
          .header input { width: 250px; }
          .content { padding: 10px; }
        }
      </style>
    </head>
    <body>
      <div class="header">
        <h1>CrystalDocs Search</h1>
        <div class="search">
          <form action="/search" method="get">
            <input type="text" name="q" value="#{query}" placeholder="Search Crystal packages and documentation..." autofocus />
            <button type="submit">Search</button>
          </form>
        </div>
      </div>
      <div class="content">
        #{if query.empty?
          <<-CONTENT
          <div class="suggestions">
            <h4>Popular Packages</h4>
            <p>Try searching for: <a href="/search?q=kemal">kemal</a>, <a href="/search?q=crystal-pg">crystal-pg</a>, <a href="/search?q=ameba">ameba</a></p>
          </div>
          CONTENT
        elsif results.empty?
          <<-CONTENT
          <div class="results-info">
            No results found for "#{query}"
          </div>
          <div class="no-results">
            <h3>No documentation found</h3>
            <p>Try a different search term or browse all packages.</p>
            <p><a href="/api/v1/docs" style="color: #007bff;">View all documentation builds</a></p>
          </div>
          CONTENT
        else
          results_html = String.build do |str|
            str << <<-CONTENT
            <div class="results-info">
              Found #{results.size} result#{"s" if results.size != 1} for "#{query}"
            </div>
            CONTENT
            
            results.each do |result|
              shard_name = result["shard_name"].as(String)
              version = result["version"].as(String)
              description = result["description"].as(String?)
              github_repo = result["github_repo"].as(String)
              build_status = result["build_status"].as(String)
              file_count = result["file_count"].as(Int32)
              created_at = result["created_at"].as(Time)
              
              status_badge = case build_status
              when "success" then "<span style='color: green; font-weight: bold;'>✓ Built</span>"
              when "building" then "<span style='color: orange;'>⚡ Building</span>"
              when "failed" then "<span style='color: red;'>✗ Failed</span>"
              else "<span style='color: gray;'>○ Pending</span>"
              end
              
              str << <<-RESULT
              <div class="result">
                <h3><a href="/docs/#{shard_name}/#{version}">#{shard_name}</a></h3>
                <div class="meta">
                  Version #{version} • #{status_badge} • #{file_count} files • 
                  <a href="https://github.com/#{github_repo}" target="_blank">#{github_repo}</a> • 
                  #{created_at.to_s("%B %-d, %Y")}
                </div>
                <div class="description">#{description || "Crystal package documentation"}</div>
              </div>
              RESULT
            end
          end
          results_html
        end}
      </div>
    </body>
    </html>
    HTML
  end
  
  # API endpoint for documentation data
  get "/api/v1/docs/:package" do |env|
    env.response.content_type = "application/json"
    package = env.params.url["package"]
    version = env.params.query["version"]? || "latest"
    
    # Try to find documentation in database
    # This would normally query by shard name, for now return placeholder
    {
      package: package,
      version: version,
      documentation: {
        readme: "",
        api: [] of String,
        examples: [] of String
      },
      generated_at: Time.utc.to_s,
      build_status: "pending"
    }.to_json
  end
  
  # Trigger documentation build
  post "/api/v1/docs/:package/build" do |env|
    env.response.content_type = "application/json"
    package = env.params.url["package"]
    
    begin
      body = env.request.body.try(&.gets_to_end) || "{}"
      data = JSON.parse(body)
      
      shard_id = data["shard_id"]?.try(&.as_i) || 1
      version = data["version"]?.try(&.as_s) || "latest"
      github_repo = data["github_repo"]?.try(&.as_s) || "#{package}/#{package}"
      
      content_path = "#{package}/#{version}"
      
      # Create documentation record
      doc_id = DocumentationRepository.create(shard_id, version, content_path)
      
      if doc_id
        # Start build job
        job_name = DocBuildService.create_build_job(package, version, github_repo, content_path)
        
        if job_name
          {
            status: "success",
            message: "Documentation build started",
            job_name: job_name,
            documentation_id: doc_id
          }.to_json
        else
          env.response.status_code = 500
          {
            status: "error", 
            message: "Failed to start documentation build job"
          }.to_json
        end
      else
        env.response.status_code = 500
        {
          status: "error",
          message: "Failed to create documentation record"
        }.to_json
      end
    rescue ex : Exception
      env.response.status_code = 400
      {
        status: "error",
        message: "Invalid request: #{ex.message}"
      }.to_json
    end
  end
  
  # Get build status
  get "/api/v1/docs/:package/build-status" do |env|
    env.response.content_type = "application/json"
    package = env.params.url["package"]
    version = env.params.query["version"]? || "latest"
    
    content_path = "#{package}/#{version}"
    doc = DocumentationRepository.find_by_content_path(content_path)
    
    if doc
      {
        status: doc["build_status"],
        version: doc["version"],
        content_path: doc["content_path"],
        file_count: doc["file_count"],
        size_bytes: doc["size_bytes"],
        created_at: doc["created_at"],
        updated_at: doc["updated_at"],
        build_log: doc["build_log"]
      }.to_json
    else
      env.response.status_code = 404
      {
        status: "not_found",
        message: "Documentation not found for #{package}:#{version}"
      }.to_json
    end
  end
  
  # List all documentation builds
  get "/api/v1/docs" do |env|
    env.response.content_type = "application/json"
    limit = env.params.query["limit"]?.try(&.to_i) || 50
    
    docs = DocumentationRepository.list_recent(limit)
    
    {
      status: "success",
      count: docs.size,
      documentation: docs.map do |doc|
        {
          id: doc["id"],
          shard_name: doc["shard_name"],
          version: doc["version"],
          build_status: doc["build_status"],
          file_count: doc["file_count"],
          size_bytes: doc["size_bytes"],
          created_at: doc["created_at"],
          updated_at: doc["updated_at"]
        }
      end
    }.to_json
  end
  
  # Build statistics endpoint
  get "/api/v1/build-stats" do |env|
    env.response.content_type = "application/json"
    
    stats = DocumentationRepository.get_build_stats
    job_stats = DocBuildService.list_build_jobs
    storage_stats = DocStorageService.get_storage_stats
    
    {
      status: "success",
      database_stats: stats,
      storage_stats: storage_stats,
      active_jobs: job_stats.select { |job| job[:status] == "running" }.size,
      pending_jobs: job_stats.select { |job| job[:status] == "pending" }.size,
      total_jobs: job_stats.size
    }.to_json
  end
  
  # Serve documentation content
  get "/docs/:package/:version" do |env|
    package = env.params.url["package"]
    version = env.params.url["version"]
    file_path = env.params.query["file"]? || "index.html"
    
    content_path = "#{package}/#{version}"
    
    # Check if documentation exists in storage
    if DocStorageService.documentation_exists?(content_path)
      content = DocStorageService.get_documentation_file(content_path, file_path)
      
      if content
        # Enhance the content with navigation and version switching
        enhanced_content = DocParserService.enhance_documentation(content, package, version)
        enhanced_content = add_version_switcher(enhanced_content, package, version)
        
        env.response.content_type = get_content_type(file_path)
        enhanced_content
      else
        env.response.status_code = 404
        "Documentation file not found"
      end
    else
      env.response.status_code = 404
      env.response.content_type = "text/html"
      
      # Check if build is in progress
      doc = DocumentationRepository.find_by_content_path(content_path)
      
      if doc && (doc["build_status"] == "building" || doc["build_status"] == "pending")
        build_status_page(package, version, doc["build_status"].as(String))
      else
        documentation_not_found_page(package, version)
      end
    end
  end
  
  # List files in documentation
  get "/api/v1/docs/:package/:version/files" do |env|
    env.response.content_type = "application/json"
    package = env.params.url["package"]
    version = env.params.url["version"]
    
    content_path = "#{package}/#{version}"
    files = DocStorageService.list_documentation_files(content_path)
    
    {
      status: "success",
      package: package,
      version: version,
      files: files
    }.to_json
  end
  
  # Get documentation file via API
  get "/api/v1/docs/:package/:version/content" do |env|
    env.response.content_type = "application/json"
    package = env.params.url["package"]
    version = env.params.url["version"]
    file_path = env.params.query["file"]? || "index.html"
    
    content_path = "#{package}/#{version}"
    content = DocStorageService.get_documentation_file(content_path, file_path)
    
    if content
      {
        status: "success",
        package: package,
        version: version,
        file: file_path,
        content: content,
        url: DocStorageService.get_documentation_url(content_path, file_path)
      }.to_json
    else
      env.response.status_code = 404
      {
        status: "not_found",
        message: "Documentation file not found"
      }.to_json
    end
  end
  
  # Storage health check endpoint
  get "/api/v1/storage/health" do |env|
    env.response.content_type = "application/json"
    
    is_healthy = DocStorageService.health_check
    
    {
      status: is_healthy ? "healthy" : "unhealthy",
      storage_accessible: is_healthy,
      timestamp: Time.utc.to_s
    }.to_json
  end
  
  # Get documentation metadata and structure
  get "/api/v1/docs/:package/:version/metadata" do |env|
    env.response.content_type = "application/json"
    package = env.params.url["package"]
    version = env.params.url["version"]
    
    content_path = "#{package}/#{version}"
    content = DocStorageService.get_documentation_file(content_path, "index.html")
    
    if content
      metadata = DocParserService.parse_documentation(content, package, version)
      
      {
        status: "success",
        metadata: metadata
      }.to_json
    else
      env.response.status_code = 404
      {
        status: "not_found",
        message: "Documentation content not found"
      }.to_json
    end
  end
  
  # List all available versions for a package
  get "/api/v1/docs/:package/versions" do |env|
    env.response.content_type = "application/json"
    package = env.params.url["package"]
    
    begin
      # Query database for shard by name first
      shard = CrystalDocs::DB.query_one?(
        "SELECT id FROM shards WHERE name = $1",
        package
      ) do |rs|
        rs.read(Int32)
      end
      
      if shard
        docs = DocumentationRepository.list_by_shard_id(shard)
        
        versions = docs.map do |doc|
          {
            version: doc["version"],
            build_status: doc["build_status"],
            file_count: doc["file_count"],
            size_bytes: doc["size_bytes"],
            created_at: doc["created_at"],
            updated_at: doc["updated_at"],
            url: "/docs/#{package}/#{doc["version"]}"
          }
        end
        
        {
          status: "success",
          package: package,
          versions: versions
        }.to_json
      else
        env.response.status_code = 404
        {
          status: "not_found",
          message: "Package '#{package}' not found"
        }.to_json
      end
    rescue ex : Exception
      env.response.status_code = 500
      {
        status: "error",
        message: "Error fetching versions: #{ex.message}"
      }.to_json
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
  
  # Helper method to determine content type
  def get_content_type(file_path : String) : String
    case File.extname(file_path).downcase
    when ".html", ".htm"
      "text/html"
    when ".css"
      "text/css"
    when ".js"
      "application/javascript"
    when ".json"
      "application/json"
    when ".png"
      "image/png"
    when ".jpg", ".jpeg"
      "image/jpeg"
    when ".gif"
      "image/gif"
    when ".svg"
      "image/svg+xml"
    when ".pdf"
      "application/pdf"
    else
      "text/plain"
    end
  end
  
  # Build status page
  def build_status_page(package : String, version : String, status : String) : String
    status_message = case status
    when "pending"
      "Documentation build is queued and will start shortly."
    when "building"
      "Documentation is currently being generated. Please check back in a few minutes."
    else
      "Documentation build status: #{status}"
    end
    
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>#{package}:#{version} - Building Documentation</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <meta http-equiv="refresh" content="30">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; text-align: center; }
        .status { background: #fff3cd; border: 1px solid #ffeaa7; padding: 20px; margin: 20px auto; max-width: 600px; border-radius: 4px; }
        .spinner { border: 4px solid #f3f3f3; border-top: 4px solid #007bff; border-radius: 50%; width: 40px; height: 40px; animation: spin 1s linear infinite; margin: 20px auto; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        .actions { margin-top: 20px; }
        .btn { background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block; margin: 5px; }
        .btn:hover { background: #0056b3; }
      </style>
    </head>
    <body>
      <h1>#{package}:#{version}</h1>
      <div class="status">
        <div class="spinner"></div>
        <h3>Documentation Build in Progress</h3>
        <p>#{status_message}</p>
        <p><small>This page will refresh automatically every 30 seconds.</small></p>
      </div>
      <div class="actions">
        <a href="/api/v1/docs/#{package}/build-status?version=#{version}" class="btn">Check API Status</a>
        <a href="/" class="btn">Back to Home</a>
      </div>
    </body>
    </html>
    HTML
  end
  
  # Documentation not found page
  def documentation_not_found_page(package : String, version : String) : String
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>#{package}:#{version} - Documentation Not Found</title>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 40px; text-align: center; }
        .error { background: #f8d7da; border: 1px solid #f5c6cb; padding: 20px; margin: 20px auto; max-width: 600px; border-radius: 4px; color: #721c24; }
        .actions { margin-top: 20px; }
        .btn { background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block; margin: 5px; }
        .btn:hover { background: #0056b3; }
        .btn.primary { background: #28a745; }
        .btn.primary:hover { background: #218838; }
      </style>
    </head>
    <body>
      <h1>#{package}:#{version}</h1>
      <div class="error">
        <h3>Documentation Not Found</h3>
        <p>Documentation for this package and version has not been generated yet.</p>
        <p>You can trigger a documentation build using the API or wait for the automatic build process.</p>
      </div>
      <div class="actions">
        <button class="btn primary" onclick="triggerBuild()">Trigger Documentation Build</button>
        <a href="/search?q=#{package}" class="btn">Search for #{package}</a>
        <a href="/" class="btn">Back to Home</a>
      </div>
      
      <script>
        function triggerBuild() {
          fetch('/api/v1/docs/#{package}/build', {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
              version: '#{version}',
              github_repo: '#{package}/#{package}'
            })
          })
          .then(response => response.json())
          .then(data => {
            if (data.status === 'success') {
              alert('Documentation build started! Refreshing page...');
              location.reload();
            } else {
              alert('Failed to start build: ' + data.message);
            }
          })
          .catch(error => {
            alert('Error triggering build: ' + error.message);
          });
        }
      </script>
    </body>
    </html>
    HTML
  end
  
  # Add version switcher to documentation
  def add_version_switcher(content : String, package : String, current_version : String) : String
    version_switcher = <<-HTML
    <div class="version-switcher" style="position: fixed; top: 20px; right: 20px; background: white; border: 1px solid #ddd; border-radius: 4px; padding: 10px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); z-index: 1000;">
      <label style="font-size: 12px; color: #666; display: block; margin-bottom: 5px;">Version:</label>
      <select id="version-selector" style="border: 1px solid #ddd; border-radius: 3px; padding: 5px;">
        <option value="#{current_version}" selected>#{current_version}</option>
      </select>
    </div>
    
    <script>
    // Load available versions
    fetch('/api/v1/docs/#{package}/versions')
      .then(response => response.json())
      .then(data => {
        if (data.status === 'success') {
          const selector = document.getElementById('version-selector');
          selector.innerHTML = '';
          
          data.versions.forEach(v => {
            const option = document.createElement('option');
            option.value = v.version;
            option.textContent = v.version + (v.build_status === 'success' ? '' : ' (' + v.build_status + ')');
            if (v.version === '#{current_version}') option.selected = true;
            selector.appendChild(option);
          });
          
          selector.addEventListener('change', function() {
            if (this.value !== '#{current_version}') {
              const currentPath = window.location.pathname;
              const newPath = currentPath.replace('/#{current_version}', '/' + this.value);
              window.location.href = newPath + window.location.search;
            }
          });
        }
      })
      .catch(error => console.log('Could not load versions:', error));
    </script>
    HTML
    
    # Add the version switcher right after the opening body tag
    if match = content.match(/(<body[^>]*>)/i)
      content.sub(match[0], "#{match[0]}\n#{version_switcher}")
    else
      content + version_switcher
    end
  end
end

# Start the server
port = ENV["PORT"]?.try(&.to_i) || 3001
puts "Starting CrystalDocs on port #{port}"
Kemal.run(port)