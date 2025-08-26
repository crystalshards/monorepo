require "redis"
# TODO: Fix cache service dependencies
# require "../../../../libraries/shared/src/services/cache_service"

module CrystalShards
  class SearchAnalyticsService
    SEARCH_QUERIES_KEY = "search:queries"
    TRENDING_KEY = "search:trending"
    USER_SEARCHES_KEY = "search:users"
    SEARCH_STATS_KEY = "search:stats"
    
    def initialize(@redis : Redis)
    end

    # Record a search query for analytics
    def record_search(query : String, results_count : Int32, user_id : String? = nil, filters : SearchOptions? = nil)
      return if query.empty? || query.size < 2

      # Normalize query for analytics
      normalized_query = query.downcase.strip

      # Record search in sorted set with timestamp score
      timestamp = Time.utc.to_unix_f
      @redis.zadd(SEARCH_QUERIES_KEY, timestamp, normalized_query)
      
      # Increment search count for trending analysis
      @redis.hincrby("#{SEARCH_QUERIES_KEY}:counts", normalized_query, 1)
      
      # Store search metadata
      search_data = {
        "query" => normalized_query,
        "results_count" => results_count,
        "timestamp" => timestamp,
        "user_id" => user_id,
        "has_filters" => filters && !filters.to_cache_key.empty?
      }.to_json
      
      @redis.lpush("#{SEARCH_QUERIES_KEY}:recent", search_data)
      @redis.ltrim("#{SEARCH_QUERIES_KEY}:recent", 0, 999) # Keep last 1000 searches
      
      # Update trending searches (more recent searches get higher weight)
      trending_score = timestamp / 3600.0 # Hour-based scoring
      @redis.zadd(TRENDING_KEY, trending_score, normalized_query)
      
      # Track user searches if user provided
      if user_id
        @redis.sadd("#{USER_SEARCHES_KEY}:#{user_id}", normalized_query)
      end

      # Update daily stats
      date_key = Time.utc.to_s("%Y-%m-%d")
      @redis.hincrby("#{SEARCH_STATS_KEY}:#{date_key}", "total_searches", 1)
      @redis.hincrby("#{SEARCH_STATS_KEY}:#{date_key}", "unique_queries", 1) if @redis.hget("#{SEARCH_QUERIES_KEY}:counts", normalized_query) == "1"
      
      # Set expiration for cleanup (30 days for detailed data)
      @redis.expire("#{SEARCH_STATS_KEY}:#{date_key}", 30 * 24 * 3600)
    end

    # Get trending search queries
    def get_trending_searches(limit = 20) : Array(Hash(String, String))
      # Get trending searches from last 7 days
      cutoff_time = (Time.utc - 7.days).to_unix_f / 3600.0
      
      trending_queries = @redis.zrevrangebyscore(TRENDING_KEY, "+inf", cutoff_time.to_s, limit: limit)
      
      results = [] of Hash(String, String)
      trending_queries.each do |query|
        count = @redis.hget("#{SEARCH_QUERIES_KEY}:counts", query) || "0"
        results << {
          "query" => query,
          "search_count" => count,
          "trending_score" => (@redis.zscore(TRENDING_KEY, query) || 0.0).to_s
        }
      end
      
      results
    end

    # Get popular search queries by total count
    def get_popular_searches(limit = 20) : Array(Hash(String, String))
      # Get most searched queries by count
      popular_queries = @redis.hgetall("#{SEARCH_QUERIES_KEY}:counts")
      
      # Sort by count and take top N
      sorted_queries = popular_queries.to_a.sort_by { |_, count| -count.to_i }
      
      results = [] of Hash(String, String)
      sorted_queries.first(limit).each do |(query, count)|
        results << {
          "query" => query,
          "search_count" => count
        }
      end
      
      results
    end

    # Get recent search queries
    def get_recent_searches(limit = 50) : Array(Hash(String, JSON::Any))
      recent_searches = @redis.lrange("#{SEARCH_QUERIES_KEY}:recent", 0, limit - 1)
      
      recent_searches.map do |search_json|
        JSON.parse(search_json).as_h
      end
    end

    # Get search statistics for a date range
    def get_search_stats(days_back = 7) : Hash(String, JSON::Any)
      stats = Hash(String, JSON::Any).new
      total_searches = 0_i64
      unique_queries = 0_i64
      daily_stats = [] of Hash(String, JSON::Any)

      days_back.times do |i|
        date = (Time.utc - i.days).to_s("%Y-%m-%d")
        day_stats = @redis.hgetall("#{SEARCH_STATS_KEY}:#{date}")
        
        day_total = day_stats["total_searches"]?.try(&.to_i64) || 0_i64
        day_unique = day_stats["unique_queries"]?.try(&.to_i64) || 0_i64
        
        total_searches += day_total
        unique_queries += day_unique
        
        daily_stats << {
          "date" => JSON::Any.new(date),
          "total_searches" => JSON::Any.new(day_total),
          "unique_queries" => JSON::Any.new(day_unique)
        }
      end

      stats["total_searches"] = JSON::Any.new(total_searches)
      stats["unique_queries"] = JSON::Any.new(unique_queries)
      stats["daily_breakdown"] = JSON::Any.new(daily_stats)
      stats["period_days"] = JSON::Any.new(days_back.to_i64)

      stats
    end

    # Clean up old search data to prevent memory bloat
    def cleanup_old_data
      # Remove searches older than 30 days from the main queries set
      cutoff_time = (Time.utc - 30.days).to_unix_f
      @redis.zremrangebyscore(SEARCH_QUERIES_KEY, "-inf", cutoff_time.to_s)
      
      # Remove old trending data (older than 30 days)  
      trending_cutoff = cutoff_time / 3600.0
      @redis.zremrangebyscore(TRENDING_KEY, "-inf", trending_cutoff.to_s)
      
      # Clean up very low count queries (count = 1 and older than 7 days)
      old_single_searches = [] of String
      @redis.hgetall("#{SEARCH_QUERIES_KEY}:counts").each do |query, count|
        if count == "1"
          # Check if this query is old
          latest_search = @redis.zscore(SEARCH_QUERIES_KEY, query)
          if latest_search && latest_search < (Time.utc - 7.days).to_unix_f
            old_single_searches << query
          end
        end
      end
      
      # Remove old single searches
      old_single_searches.each do |query|
        @redis.hdel("#{SEARCH_QUERIES_KEY}:counts", query)
        @redis.zrem(SEARCH_QUERIES_KEY, query)
        @redis.zrem(TRENDING_KEY, query)
      end
    end

    # Get personalized search suggestions based on user's search history
    def get_personalized_suggestions(user_id : String, limit = 10) : Array(String)
      return [] of String if user_id.empty?

      user_searches = @redis.smembers("#{USER_SEARCHES_KEY}:#{user_id}")
      
      # Get related searches based on user's history
      suggestions = Set(String).new
      user_searches.each do |search|
        # Find queries that start with the same words
        similar_queries = @redis.zrangebylex(SEARCH_QUERIES_KEY, "[#{search[0..1]}", "[#{search[0..1]}\xff")
        similar_queries.each do |similar|
          suggestions.add(similar) if similar != search
        end
        
        break if suggestions.size >= limit
      end
      
      suggestions.to_a.first(limit)
    end
  end
end