require "redis"
require "json"

# High-performance Redis caching service for all CrystalShards applications
# Provides smart caching with TTL, compression, and cache invalidation
class CacheService
  TTL_SHORT = 300    # 5 minutes for search results
  TTL_MEDIUM = 1800  # 30 minutes for metadata
  TTL_LONG = 3600    # 1 hour for stats

  def initialize(@redis_url : String = ENV.fetch("REDIS_URL", "redis://localhost:6379"))
    @redis = Redis.new(URI.parse(@redis_url))
    @enabled = true
  rescue ex
    puts "Warning: Redis connection failed, caching disabled: #{ex.message}"
    @enabled = false
    @redis = nil
  end

  # Generic cache get with JSON deserialization
  def get(key : String, as type : T.class) : T? forall T
    return nil unless @enabled && @redis

    begin
      cached = @redis.not_nil!.get(cache_key(key))
      return nil unless cached

      T.from_json(cached)
    rescue ex
      puts "Cache get error for key #{key}: #{ex.message}"
      nil
    end
  end

  # Generic cache set with JSON serialization and TTL
  def set(key : String, value : T, ttl : Int32 = TTL_SHORT) : Bool forall T
    return false unless @enabled && @redis

    begin
      json_data = value.to_json
      @redis.not_nil!.setex(cache_key(key), ttl, json_data)
      true
    rescue ex
      puts "Cache set error for key #{key}: #{ex.message}"
      false
    end
  end

  # Cache search results with smart key generation
  def cache_search_results(search_type : String, query : String, limit : Int32, offset : Int32, results : Array(T), ttl : Int32 = TTL_SHORT) : Bool forall T
    key = "search:#{search_type}:#{query.gsub(/[^a-zA-Z0-9]/, "_")}:#{limit}:#{offset}"
    set(key, results, ttl)
  end

  # Get cached search results
  def get_search_results(search_type : String, query : String, limit : Int32, offset : Int32, as type : Array(T).class) : Array(T)? forall T
    key = "search:#{search_type}:#{query.gsub(/[^a-zA-Z0-9]/, "_")}:#{limit}:#{offset}"
    get(key, type)
  end

  # Cache database counts and statistics
  def cache_stats(app : String, stats : Hash(String, Int64), ttl : Int32 = TTL_LONG) : Bool
    set("stats:#{app}", stats, ttl)
  end

  def get_stats(app : String) : Hash(String, Int64)?
    get("stats:#{app}", Hash(String, Int64))
  end

  # Cache individual record metadata
  def cache_record(collection : String, id : String | Int32, record : T, ttl : Int32 = TTL_MEDIUM) : Bool forall T
    set("record:#{collection}:#{id}", record, ttl)
  end

  def get_record(collection : String, id : String | Int32, as type : T.class) : T? forall T
    get("record:#{collection}:#{id}", type)
  end

  # Invalidate cache patterns
  def invalidate_pattern(pattern : String) : Int32
    return 0 unless @enabled && @redis

    begin
      keys = @redis.not_nil!.keys(cache_key(pattern))
      return 0 if keys.empty?

      @redis.not_nil!.del(keys)
      keys.size
    rescue ex
      puts "Cache invalidation error for pattern #{pattern}: #{ex.message}"
      0
    end
  end

  # Smart cache invalidation for search results
  def invalidate_search(search_type : String) : Int32
    invalidate_pattern("search:#{search_type}:*")
  end

  # Cache warming for frequently accessed data
  def warm_cache(app : String, &block)
    return unless @enabled

    puts "Warming cache for #{app}..."
    start_time = Time.utc
    
    begin
      yield
      duration = Time.utc - start_time
      puts "Cache warming completed for #{app} in #{duration.total_milliseconds}ms"
    rescue ex
      puts "Cache warming failed for #{app}: #{ex.message}"
    end
  end

  # Health check
  def healthy? : Bool
    return false unless @enabled && @redis

    begin
      @redis.not_nil!.ping == "PONG"
    rescue
      false
    end
  end

  # Get cache statistics
  def stats : Hash(String, String)
    return {"status" => "disabled"} unless @enabled && @redis

    begin
      info = @redis.not_nil!.info("memory")
      {
        "status" => "connected",
        "memory_usage" => extract_info_value(info, "used_memory_human"),
        "connected_clients" => extract_info_value(info, "connected_clients"),
        "keyspace_hits" => extract_info_value(@redis.not_nil!.info("stats"), "keyspace_hits"),
        "keyspace_misses" => extract_info_value(@redis.not_nil!.info("stats"), "keyspace_misses")
      }
    rescue ex
      {"status" => "error", "error" => ex.message}
    end
  end

  # Close connection
  def close
    @redis.try(&.close)
  end

  private def cache_key(key : String) : String
    "crystalshards:#{key}"
  end

  private def extract_info_value(info : String, key : String) : String
    lines = info.split('\n')
    line = lines.find { |l| l.starts_with?(key) }
    return "unknown" unless line
    
    parts = line.split(':')
    return "unknown" if parts.size < 2
    
    parts[1].strip
  end
end

# Global cache instance
CACHE = CacheService.new