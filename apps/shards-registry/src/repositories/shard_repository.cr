require "pg"
require "json" 
require "db"
require "../models"
require "../search_options"
require "../../../libraries/shared/src/services/cache_service"
require "../../../libraries/shared/src/services/email_service"

module CrystalShards
  class ShardRepository
    def initialize(@db : DB::Database)
    end
    
    def create(shard : CrystalShared::Shard) : CrystalShared::Shard?
      result = @db.query_one(
        "INSERT INTO shards (name, description, github_url, homepage_url, documentation_url, 
         license, latest_version, download_count, stars, forks, last_activity, tags, 
         crystal_versions, dependencies, published, featured, created_at, updated_at) 
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18) 
         RETURNING id, created_at, updated_at",
        shard.name, shard.description, shard.github_url, shard.homepage_url, 
        shard.documentation_url, shard.license, shard.latest_version, 
        shard.download_count, shard.stars, shard.forks, shard.last_activity,
        shard.tags, shard.crystal_versions, shard.dependencies.to_json,
        shard.published, shard.featured, Time.utc, Time.utc
      ) do |rs|
        shard.id = rs.read(Int32)
        shard.created_at = rs.read(Time)
        shard.updated_at = rs.read(Time)
      end
      # Invalidate search cache and stats when new shard is created
      CACHE.invalidate_search("shards")
      CACHE.invalidate_pattern("stats:registry")
      
      shard
    rescue PG::PQError
      nil
    end
    
    def find_by_id(id : Int32) : CrystalShared::Shard?
      @db.query_one?(
        "SELECT id, name, description, github_url, homepage_url, documentation_url,
         license, latest_version, download_count, stars, forks, last_activity, tags,
         crystal_versions, dependencies, published, featured, created_at, updated_at
         FROM shards WHERE id = $1", id
      ) do |rs|
        build_shard_from_result_set(rs)
      end
    end
    
    def find_by_name(name : String) : CrystalShared::Shard?
      @db.query_one?(
        "SELECT id, name, description, github_url, homepage_url, documentation_url,
         license, latest_version, download_count, stars, forks, last_activity, tags,
         crystal_versions, dependencies, published, featured, created_at, updated_at
         FROM shards WHERE name = $1", name
      ) do |rs|
        build_shard_from_result_set(rs)
      end
    end
    
    def find_by_github_url(github_url : String) : CrystalShared::Shard?
      @db.query_one?(
        "SELECT id, name, description, github_url, homepage_url, documentation_url,
         license, latest_version, download_count, stars, forks, last_activity, tags,
         crystal_versions, dependencies, published, featured, created_at, updated_at
         FROM shards WHERE github_url = $1", github_url
      ) do |rs|
        build_shard_from_result_set(rs)
      end
    end
    
    def list_published(offset = 0, limit = 20) : Array(CrystalShared::Shard)
      shards = [] of CrystalShared::Shard
      @db.query(
        "SELECT id, name, description, github_url, homepage_url, documentation_url,
         license, latest_version, download_count, stars, forks, last_activity, tags,
         crystal_versions, dependencies, published, featured, created_at, updated_at
         FROM shards WHERE published = TRUE ORDER BY stars DESC, download_count DESC
         OFFSET $1 LIMIT $2", offset, limit
      ) do |rs|
        rs.each do
          shards << build_shard_from_result_set(rs)
        end
      end
      shards
    end
    
    def search(query : String, offset = 0, limit = 20) : Array(CrystalShared::Shard)
      search(query, offset, limit, SearchOptions.new)
    end

    def search(query : String, offset = 0, limit = 20, options : SearchOptions = SearchOptions.new) : Array(CrystalShared::Shard)
      # Create cache key including filters for proper caching
      cache_key = "#{query}:#{options.to_cache_key}"
      cached_results = CACHE.get_search_results("shards", cache_key, limit, offset, Array(CrystalShared::Shard))
      return cached_results if cached_results

      # Build dynamic WHERE conditions
      where_conditions = ["published = TRUE"] of String
      query_params = [] of DB::Any
      param_index = 1

      # Add text search condition
      if !query.empty?
        where_conditions << "(to_tsvector('english', name || ' ' || COALESCE(description, '')) @@ plainto_tsquery('english', $#{param_index}) OR name ILIKE '%' || $#{param_index} || '%')"
        query_params << query
        param_index += 1
      end

      # Add license filter
      if license = options.license
        where_conditions << "LOWER(license) = LOWER($#{param_index})"
        query_params << license
        param_index += 1
      end

      # Add Crystal version compatibility filter
      if crystal_version = options.crystal_version
        where_conditions << "$#{param_index} = ANY(crystal_versions)"
        query_params << crystal_version
        param_index += 1
      end

      # Add tag filter
      if tag = options.tag
        where_conditions << "$#{param_index} = ANY(tags)"
        query_params << tag
        param_index += 1
      end

      # Add minimum stars filter
      if min_stars = options.min_stars
        where_conditions << "stars >= $#{param_index}"
        query_params << min_stars
        param_index += 1
      end

      # Add featured filter
      if options.featured_only
        where_conditions << "featured = TRUE"
      end

      # Add last activity filter (updated in last X days)
      if days = options.updated_within_days
        where_conditions << "last_activity > (NOW() - INTERVAL '#{days} days')"
      end

      # Build ORDER BY clause
      order_clause = case options.sort_by
      when "stars"
        "ORDER BY stars DESC, name ASC"
      when "downloads"
        "ORDER BY download_count DESC, name ASC"
      when "recent"
        "ORDER BY last_activity DESC NULLS LAST, created_at DESC"
      when "name"
        "ORDER BY name ASC"
      else # "relevance" or default
        if query.empty?
          "ORDER BY stars DESC, download_count DESC"
        else
          "ORDER BY ts_rank(to_tsvector('english', name || ' ' || COALESCE(description, '')), plainto_tsquery('english', $1)) DESC, stars DESC"
        end
      end

      # Build final query
      rank_select = if query.empty?
        ""
      else
        ", ts_rank(to_tsvector('english', name || ' ' || COALESCE(description, '')), plainto_tsquery('english', $1)) as rank"
      end

      sql = "SELECT id, name, description, github_url, homepage_url, documentation_url,
             license, latest_version, download_count, stars, forks, last_activity, tags,
             crystal_versions, dependencies, published, featured, created_at, updated_at#{rank_select}
             FROM shards 
             WHERE #{where_conditions.join(" AND ")}
             #{order_clause}
             OFFSET $#{param_index} LIMIT $#{param_index + 1}"

      query_params << offset << limit

      # Perform database query
      shards = [] of CrystalShared::Shard
      @db.query(sql, args: query_params) do |rs|
        rs.each do
          shards << build_shard_from_result_set(rs, has_rank: !query.empty?)
        end
      end

      # Cache the results for 5 minutes
      CACHE.cache_search_results("shards", cache_key, limit, offset, shards, CacheService::TTL_SHORT)
      
      shards
    end
    
    def count_published : Int32
      # Try cache first
      cached_stats = CACHE.get_stats("registry")
      if cached_stats && cached_stats.has_key?("published_count")
        return cached_stats["published_count"].to_i32
      end

      count = @db.scalar("SELECT COUNT(*) FROM shards WHERE published = TRUE").as(Int64).to_i32
      
      # Cache the count with other stats
      stats = {"published_count" => count.to_i64}
      CACHE.cache_stats("registry", stats, CacheService::TTL_MEDIUM)
      
      count
    end
    
    def count_search(query : String) : Int32
      count_search(query, SearchOptions.new)
    end

    def count_search(query : String, options : SearchOptions) : Int32
      # Build same WHERE conditions as search method
      where_conditions = ["published = TRUE"] of String
      query_params = [] of DB::Any
      param_index = 1

      # Add text search condition
      if !query.empty?
        where_conditions << "(to_tsvector('english', name || ' ' || COALESCE(description, '')) @@ plainto_tsquery('english', $#{param_index}) OR name ILIKE '%' || $#{param_index} || '%')"
        query_params << query
        param_index += 1
      end

      # Add license filter
      if license = options.license
        where_conditions << "LOWER(license) = LOWER($#{param_index})"
        query_params << license
        param_index += 1
      end

      # Add Crystal version compatibility filter
      if crystal_version = options.crystal_version
        where_conditions << "$#{param_index} = ANY(crystal_versions)"
        query_params << crystal_version
        param_index += 1
      end

      # Add tag filter
      if tag = options.tag
        where_conditions << "$#{param_index} = ANY(tags)"
        query_params << tag
        param_index += 1
      end

      # Add minimum stars filter
      if min_stars = options.min_stars
        where_conditions << "stars >= $#{param_index}"
        query_params << min_stars
        param_index += 1
      end

      # Add featured filter
      if options.featured_only
        where_conditions << "featured = TRUE"
      end

      # Add last activity filter
      if days = options.updated_within_days
        where_conditions << "last_activity > (NOW() - INTERVAL '#{days} days')"
      end

      sql = "SELECT COUNT(*) FROM shards WHERE #{where_conditions.join(" AND ")}"

      @db.scalar(sql, args: query_params).as(Int64).to_i32
    end
    
    def update_github_stats(id : Int32, stars : Int32, forks : Int32, last_activity : Time?) : Bool
      @db.exec(
        "UPDATE shards SET stars = $1, forks = $2, last_activity = $3, updated_at = $4 
         WHERE id = $5", stars, forks, last_activity, Time.utc, id
      )
      
      # Invalidate search cache since stats affect ranking
      CACHE.invalidate_search("shards")
      CACHE.invalidate_pattern("record:shards:#{id}")
      
      true
    rescue
      false
    end
    
    def publish(id : Int32) : Bool
      @db.exec("UPDATE shards SET published = TRUE, updated_at = $1 WHERE id = $2", Time.utc, id)
      
      # Invalidate all caches when publication status changes
      CACHE.invalidate_search("shards")
      CACHE.invalidate_pattern("stats:registry")
      CACHE.invalidate_pattern("record:shards:#{id}")
      
      # Send publication notification
      spawn do
        begin
          shard = find_by_id(id)
          if shard
            # Extract author email from GitHub URL if possible
            # In production, this would come from user accounts
            author_email = "author@example.com" # Placeholder
            EMAIL_SERVICE.send_shard_notification(shard.name, author_email, shard.github_url)
          end
        rescue ex
          puts "Shard publication email notification failed: #{ex.message}"
        end
      end
      
      true
    rescue
      false
    end
    
    def unpublish(id : Int32) : Bool
      @db.exec("UPDATE shards SET published = FALSE, updated_at = $1 WHERE id = $2", Time.utc, id)
      
      # Invalidate all caches when publication status changes
      CACHE.invalidate_search("shards")
      CACHE.invalidate_pattern("stats:registry")
      CACHE.invalidate_pattern("record:shards:#{id}")
      
      true
    rescue
      false
    end

    def get_available_filters : Hash(String, Array(String))
      cached_filters = CACHE.get_stats("filters")
      if cached_filters
        return cached_filters.transform_values { |v| v.as(Array(JSON::Any)).map(&.as_s) }
      end

      filters = Hash(String, Array(String)).new

      # Get available licenses
      licenses = [] of String
      @db.query("SELECT DISTINCT license FROM shards WHERE published = TRUE AND license IS NOT NULL ORDER BY license") do |rs|
        rs.each { licenses << rs.read(String) }
      end
      filters["licenses"] = licenses

      # Get available Crystal versions
      crystal_versions = Set(String).new
      @db.query("SELECT DISTINCT UNNEST(crystal_versions) as version FROM shards WHERE published = TRUE ORDER BY version") do |rs|
        rs.each { crystal_versions.add(rs.read(String)) }
      end
      filters["crystal_versions"] = crystal_versions.to_a

      # Get available tags  
      tags = Set(String).new
      @db.query("SELECT DISTINCT UNNEST(tags) as tag FROM shards WHERE published = TRUE ORDER BY tag") do |rs|
        rs.each { tags.add(rs.read(String)) }
      end
      filters["tags"] = tags.to_a

      # Cache for 1 hour
      CACHE.cache_stats("filters", filters.transform_values { |v| v.map(&.as(JSON::Any)) }, CacheService::TTL_LONG)
      
      filters
    end

    def get_search_suggestions(query : String, limit = 10) : Array(Hash(String, String))
      return [] of Hash(String, String) if query.empty? || query.size < 2

      suggestions = [] of Hash(String, String)
      
      # Get shard name suggestions (exact prefix matches prioritized)
      @db.query(
        "SELECT name, description, stars FROM shards 
         WHERE published = TRUE 
         AND (name ILIKE $1 || '%' OR name ILIKE '%' || $1 || '%')
         ORDER BY 
           CASE WHEN name ILIKE $1 || '%' THEN 0 ELSE 1 END,
           stars DESC
         LIMIT $2", query, limit
      ) do |rs|
        rs.each do
          name = rs.read(String)
          description = rs.read(String?)
          stars = rs.read(Int32)
          
          suggestions << {
            "type" => "shard",
            "text" => name,
            "description" => description || "",
            "stars" => stars.to_s
          }
        end
      end

      # If we need more suggestions, add tag suggestions
      if suggestions.size < limit
        remaining_limit = limit - suggestions.size
        @db.query(
          "SELECT DISTINCT UNNEST(tags) as tag, COUNT(*) as shard_count 
           FROM shards 
           WHERE published = TRUE 
           AND UNNEST(tags) ILIKE '%' || $1 || '%'
           GROUP BY tag 
           ORDER BY shard_count DESC, tag ASC
           LIMIT $2", query, remaining_limit
        ) do |rs|
          rs.each do
            tag = rs.read(String)
            count = rs.read(Int64)
            
            suggestions << {
              "type" => "tag",
              "text" => tag,
              "description" => "#{count} shards",
              "stars" => ""
            }
          end
        end
      end

      suggestions
    end
    
    private def build_shard_from_result_set(rs : DB::ResultSet, has_rank = false) : CrystalShared::Shard
      id = rs.read(Int32)
      name = rs.read(String)
      shard = CrystalShared::Shard.new(name, rs.read(String)) # github_url
      shard.id = id
      shard.description = rs.read(String?)
      shard.homepage_url = rs.read(String?)
      shard.documentation_url = rs.read(String?)
      shard.license = rs.read(String?)
      shard.latest_version = rs.read(String?)
      shard.download_count = rs.read(Int32)
      shard.stars = rs.read(Int32)
      shard.forks = rs.read(Int32)
      shard.last_activity = rs.read(Time?)
      shard.tags = rs.read(Array(String))
      shard.crystal_versions = rs.read(Array(String))
      
      # Parse dependencies JSON
      deps_json = rs.read(String?)
      if deps_json
        shard.dependencies = Hash(String, String).from_json(deps_json)
      end
      
      shard.published = rs.read(Bool)
      shard.featured = rs.read(Bool)
      shard.created_at = rs.read(Time)
      shard.updated_at = rs.read(Time)
      
      # Skip rank if it exists
      rs.read if has_rank
      
      shard
    end
  end
end