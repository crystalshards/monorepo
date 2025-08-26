require "db"
require "pool/connection"

# High-performance database connection pool with monitoring and optimization
class DatabasePool
  POOL_SIZE_MIN = 5
  POOL_SIZE_MAX = 50
  CONNECTION_TIMEOUT = 10.seconds
  IDLE_TIMEOUT = 300.seconds # 5 minutes
  MAX_LIFETIME = 3600.seconds # 1 hour

  property pool_stats = {
    total_connections: 0_i64,
    active_connections: 0_i64,
    idle_connections: 0_i64,
    total_queries: 0_i64,
    failed_queries: 0_i64,
    avg_query_time: 0.0,
    pool_exhausted_count: 0_i64
  }

  def initialize(@database_url : String, @pool_size : Int32 = 10)
    @pool_size = [@pool_size.clamp(POOL_SIZE_MIN, POOL_SIZE_MAX), POOL_SIZE_MAX].min
    @start_time = Time.utc
    
    # Initialize database pool with optimized settings
    @db = DB.open(@database_url) do |db|
      db.pool_size = @pool_size
      db.initial_pool_size = [@pool_size // 2, 3].max
      db.max_pool_size = @pool_size
      db.timeout = CONNECTION_TIMEOUT
      db.retry_attempts = 3
      db.retry_delay = 1.second
    end

    puts "Database pool initialized: #{@pool_size} connections to #{sanitize_url(@database_url)}"
  rescue ex
    puts "Failed to initialize database pool: #{ex.message}"
    raise ex
  end

  # Execute a query with performance monitoring
  def query(sql : String, *args, &block)
    start_time = Time.utc
    @pool_stats[:total_queries] += 1

    begin
      result = @db.query(sql, *args) do |rs|
        yield rs
      end
      
      # Update performance metrics
      query_time = (Time.utc - start_time).total_milliseconds
      update_avg_query_time(query_time)
      
      result
    rescue ex : DB::PoolTimeout
      @pool_stats[:pool_exhausted_count] += 1
      puts "WARNING: Database pool exhausted (#{@pool_stats[:pool_exhausted_count]} times)"
      raise ex
    rescue ex
      @pool_stats[:failed_queries] += 1
      puts "Database query failed: #{ex.message}"
      puts "SQL: #{sql}"
      raise ex
    end
  end

  # Execute a scalar query
  def scalar(sql : String, *args)
    start_time = Time.utc
    @pool_stats[:total_queries] += 1

    begin
      result = @db.scalar(sql, *args)
      
      # Update performance metrics  
      query_time = (Time.utc - start_time).total_milliseconds
      update_avg_query_time(query_time)
      
      result
    rescue ex : DB::PoolTimeout
      @pool_stats[:pool_exhausted_count] += 1
      puts "WARNING: Database pool exhausted (#{@pool_stats[:pool_exhausted_count]} times)"
      raise ex
    rescue ex
      @pool_stats[:failed_queries] += 1
      puts "Database scalar query failed: #{ex.message}"
      raise ex
    end
  end

  # Execute a command (INSERT, UPDATE, DELETE)
  def exec(sql : String, *args)
    start_time = Time.utc
    @pool_stats[:total_queries] += 1

    begin
      result = @db.exec(sql, *args)
      
      # Update performance metrics
      query_time = (Time.utc - start_time).total_milliseconds  
      update_avg_query_time(query_time)
      
      result
    rescue ex : DB::PoolTimeout
      @pool_stats[:pool_exhausted_count] += 1
      puts "WARNING: Database pool exhausted (#{@pool_stats[:pool_exhausted_count]} times)"
      raise ex
    rescue ex
      @pool_stats[:failed_queries] += 1
      puts "Database exec failed: #{ex.message}"
      raise ex
    end
  end

  # Execute within a transaction
  def transaction(&block)
    start_time = Time.utc
    @pool_stats[:total_queries] += 1

    begin
      result = @db.transaction do |tx|
        yield tx
      end

      query_time = (Time.utc - start_time).total_milliseconds
      update_avg_query_time(query_time)

      result
    rescue ex : DB::PoolTimeout
      @pool_stats[:pool_exhausted_count] += 1
      puts "WARNING: Database pool exhausted during transaction"
      raise ex
    rescue ex
      @pool_stats[:failed_queries] += 1
      puts "Database transaction failed: #{ex.message}"
      raise ex
    end
  end

  # Get detailed pool statistics
  def stats : Hash(String, Float64 | Int64 | String)
    uptime = Time.utc - @start_time
    success_rate = if @pool_stats[:total_queries] > 0
                     ((@pool_stats[:total_queries] - @pool_stats[:failed_queries]) * 100.0 / @pool_stats[:total_queries])
                   else
                     100.0
                   end

    {
      "pool_size" => @pool_size.to_i64,
      "total_queries" => @pool_stats[:total_queries],
      "successful_queries" => @pool_stats[:total_queries] - @pool_stats[:failed_queries],
      "failed_queries" => @pool_stats[:failed_queries],
      "success_rate_percent" => success_rate,
      "avg_query_time_ms" => @pool_stats[:avg_query_time],
      "pool_exhausted_count" => @pool_stats[:pool_exhausted_count],
      "uptime_seconds" => uptime.total_seconds,
      "queries_per_second" => @pool_stats[:total_queries] / uptime.total_seconds,
      "database_url" => sanitize_url(@database_url)
    }
  end

  # Health check for the database connection
  def healthy? : Bool
    begin
      @db.scalar("SELECT 1").as(Int32) == 1
    rescue
      false
    end
  end

  # Warm up the connection pool
  def warm_up
    puts "Warming up database connection pool..."
    start_time = Time.utc

    # Execute a simple query on multiple connections to populate the pool
    warmup_queries = [@pool_size // 2, 3].max

    warmup_queries.times do |i|
      spawn do
        begin
          @db.scalar("SELECT 1")
        rescue ex
          puts "Pool warmup query #{i + 1} failed: #{ex.message}"
        end
      end
    end

    # Wait a moment for warmup to complete
    sleep(0.5)

    duration = Time.utc - start_time
    puts "Database pool warmup completed in #{duration.total_milliseconds}ms"
  end

  # Close all connections
  def close
    @db.close
  end

  # Print performance summary
  def print_stats
    stats_data = stats
    
    puts "\n=== Database Pool Statistics ==="
    puts "Pool Size: #{stats_data["pool_size"]}"
    puts "Total Queries: #{stats_data["total_queries"]}"
    puts "Success Rate: #{stats_data["success_rate_percent"].round(2)}%"
    puts "Average Query Time: #{stats_data["avg_query_time_ms"].round(2)}ms"
    puts "Queries Per Second: #{stats_data["queries_per_second"].round(2)}"
    puts "Pool Exhaustions: #{stats_data["pool_exhausted_count"]}"
    puts "Uptime: #{(stats_data["uptime_seconds"].as(Float64) / 60).round(1)} minutes"
    puts "Database: #{stats_data["database_url"]}"
    puts "===================================\n"
  end

  # Auto-tune pool size based on usage patterns
  def auto_tune
    return if @pool_stats[:total_queries] < 100 # Need some data first

    exhaustion_rate = @pool_stats[:pool_exhausted_count].to_f / @pool_stats[:total_queries]
    
    if exhaustion_rate > 0.01 # More than 1% exhaustion rate
      new_size = [@pool_size + 2, POOL_SIZE_MAX].min
      if new_size > @pool_size
        puts "Auto-tuning: Increasing pool size from #{@pool_size} to #{new_size}"
        @pool_size = new_size
        # Note: In practice, you'd need to recreate the pool with new size
      end
    elsif exhaustion_rate < 0.001 && @pool_size > POOL_SIZE_MIN # Less than 0.1% and can reduce
      new_size = [@pool_size - 1, POOL_SIZE_MIN].max
      if new_size < @pool_size
        puts "Auto-tuning: Decreasing pool size from #{@pool_size} to #{new_size}"
        @pool_size = new_size  
      end
    end
  end

  private def update_avg_query_time(new_time : Float64)
    # Simple moving average
    @pool_stats[:avg_query_time] = (@pool_stats[:avg_query_time] * 0.9) + (new_time * 0.1)
  end

  private def sanitize_url(url : String) : String
    # Remove password from URL for logging
    url.gsub(/:([^@:]+)@/, ":***@")
  end
end

# Global database pools for each application
class DatabaseManager
  @@pools = {} of String => DatabasePool

  def self.register_pool(name : String, database_url : String, pool_size : Int32 = 10)
    @@pools[name] = DatabasePool.new(database_url, pool_size)
    @@pools[name].warm_up
  end

  def self.get_pool(name : String) : DatabasePool
    pool = @@pools[name]?
    raise "Database pool '#{name}' not found. Available pools: #{@@pools.keys}" unless pool
    pool
  end

  def self.all_pools : Hash(String, DatabasePool)
    @@pools
  end

  def self.print_all_stats
    puts "\n🔥 DATABASE POOLS SUMMARY 🔥"
    @@pools.each do |name, pool|
      puts "\n--- #{name.upcase} ---"
      pool.print_stats
    end
  end

  def self.health_check : Hash(String, Bool)
    @@pools.transform_values(&.healthy?)
  end

  def self.close_all
    @@pools.each_value(&.close)
    @@pools.clear
  end
end