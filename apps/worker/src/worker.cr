require "sidekiq"
require "pg"
require "redis"
require "http/client"
require "cr-dotenv"

# Load environment variables
Dotenv.load

module CrystalWorker
  VERSION = "0.1.0"
  
  # Configuration
  DATABASE_URL = ENV["DATABASE_URL"]? || "postgres://postgres:password@localhost/crystalshards_development"
  REDIS_URL = ENV["REDIS_URL"]? || "redis://localhost:6379"
  
  # Initialize database connection
  DB = PG.connect(DATABASE_URL)
  
  # Documentation generation job
  class DocumentationJob
    include Sidekiq::Job
    
    def perform(shard_name : String, version : String, github_url : String)
      puts "Generating documentation for #{shard_name} v#{version}"
      
      # Create a temporary directory for the build
      temp_dir = "/tmp/doc-build-#{shard_name}-#{Time.utc.to_unix}"
      
      begin
        # Clone the repository
        result = Process.run("git", ["clone", github_url, temp_dir], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
        
        if result.success?
          puts "Cloned #{github_url} successfully"
          
          # Change to the directory and generate docs
          Dir.cd(temp_dir) do
            # Install dependencies
            deps_result = Process.run("shards", ["install"], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
            
            if deps_result.success?
              # Generate documentation
              doc_result = Process.run("crystal", ["docs"], output: Process::Redirect::Pipe, error: Process::Redirect::Pipe)
              
              if doc_result.success?
                puts "Documentation generated for #{shard_name}"
                
                # TODO: Upload generated docs to MinIO storage
                # TODO: Update database with documentation status
                # TODO: Invalidate cache for this shard's docs
                
              else
                puts "Failed to generate docs for #{shard_name}: #{doc_result.error}"
              end
            else
              puts "Failed to install dependencies for #{shard_name}: #{deps_result.error}"
            end
          end
        else
          puts "Failed to clone #{github_url}: #{result.error}"
        end
        
      ensure
        # Clean up temp directory
        if Dir.exists?(temp_dir)
          Process.run("rm", ["-rf", temp_dir])
        end
      end
    end
  end
  
  # Shard indexing job
  class ShardIndexingJob
    include Sidekiq::Job
    
    def perform(github_url : String)
      puts "Indexing shard from #{github_url}"
      
      # Extract owner and repo from GitHub URL
      if match = github_url.match(/github\.com\/([^\/]+)\/([^\/]+)/)
        owner = match[1]
        repo = match[2]
        
        # Fetch repository information from GitHub API
        client = HTTP::Client.new("api.github.com", tls: true)
        client.before_request do |request|
          request.headers["User-Agent"] = "CrystalShards/1.0"
          request.headers["Accept"] = "application/vnd.github.v3+json"
          
          # Add GitHub token if available
          if github_token = ENV["GITHUB_TOKEN"]?
            request.headers["Authorization"] = "token #{github_token}"
          end
        end
        
        begin
          response = client.get("/repos/#{owner}/#{repo}")
          
          if response.status_code == 200
            puts "Successfully fetched repository info for #{owner}/#{repo}"
            
            # TODO: Parse repository data and update database
            # TODO: Extract shard.yml information
            # TODO: Index package for search
            # TODO: Schedule documentation generation
            
          else
            puts "Failed to fetch repository info: #{response.status_code}"
          end
        rescue ex
          puts "Error fetching repository info: #{ex.message}"
        ensure
          client.close
        end
      else
        puts "Invalid GitHub URL format: #{github_url}"
      end
    end
  end
  
  # Search index update job
  class SearchIndexJob
    include Sidekiq::Job
    
    def perform(shard_id : Int32)
      puts "Updating search index for shard ID #{shard_id}"
      
      # TODO: Fetch shard information from database
      # TODO: Update search index (could be Elasticsearch, Redis, or database FTS)
      # TODO: Update related caches
      
      puts "Search index updated for shard ID #{shard_id}"
    end
  end
  
  # Email notification job
  class NotificationJob
    include Sidekiq::Job
    
    def perform(type : String, data : Hash(String, String))
      puts "Sending notification: #{type}"
      
      case type
      when "shard_published"
        # Send email to shard maintainer
        puts "Shard published notification sent"
      when "docs_generated"
        # Notify that documentation is ready
        puts "Documentation ready notification sent"
      when "job_posted"
        # Notify job board subscribers
        puts "New job notification sent"
      else
        puts "Unknown notification type: #{type}"
      end
    end
  end
  
  # Search analytics cleanup job
  class SearchAnalyticsCleanupJob
    include Sidekiq::Job
    
    def perform
      puts "Running search analytics cleanup..."
      
      begin
        # Initialize Redis connection for analytics
        redis = Redis.new(url: REDIS_URL)
        
        # Clean up old search queries (>30 days)
        cutoff_time = (Time.utc - 30.days).to_unix_f
        redis.zremrangebyscore("search:queries", "-inf", cutoff_time.to_s)
        
        # Clean up old trending data
        trending_cutoff = cutoff_time / 3600.0
        redis.zremrangebyscore("search:trending", "-inf", trending_cutoff.to_s)
        
        # Clean up single-use searches older than 7 days
        queries = redis.hgetall("search:queries:counts")
        old_queries = [] of String
        
        queries.each do |query, count|
          if count == "1"
            query_time = redis.zscore("search:queries", query)
            if query_time && query_time < (Time.utc - 7.days).to_unix_f
              old_queries << query
            end
          end
        end
        
        # Remove old single-use queries
        old_queries.each do |query|
          redis.hdel("search:queries:counts", query)
          redis.zrem("search:queries", query)
          redis.zrem("search:trending", query)
        end
        
        redis.close
        puts "✓ Search analytics cleanup completed: removed #{old_queries.size} old queries"
        
      rescue ex
        puts "✗ Search analytics cleanup failed: #{ex.message}"
      end
    end
  end

  # Health check job
  class HealthCheckJob
    include Sidekiq::Job
    
    def perform
      puts "Running health checks..."
      
      # Check database connection
      begin
        DB.exec("SELECT 1")
        puts "✓ Database connection OK"
      rescue ex
        puts "✗ Database connection failed: #{ex.message}"
      end
      
      # Check Redis connection
      begin
        redis = Redis.new(url: REDIS_URL)
        redis.ping
        redis.close
        puts "✓ Redis connection OK"
      rescue ex
        puts "✗ Redis connection failed: #{ex.message}"
      end
      
      puts "Health checks completed"
    end
  end
end

# Configure Sidekiq
Sidekiq.configure_server do |config|
  config.redis = { url: CrystalWorker::REDIS_URL }
end

# Start the worker
puts "Starting CrystalWorker v#{CrystalWorker::VERSION}"
puts "Redis URL: #{CrystalWorker::REDIS_URL}"
puts "Database URL: #{CrystalWorker::DATABASE_URL[0...20]}..."

# Schedule recurring health checks
spawn do
  loop do
    CrystalWorker::HealthCheckJob.async.perform
    sleep 5.minutes
  end
end

# Schedule daily search analytics cleanup
spawn do
  loop do
    CrystalWorker::SearchAnalyticsCleanupJob.async.perform
    sleep 24.hours
  end
end

# Start Sidekiq server
Sidekiq::Server.new.start