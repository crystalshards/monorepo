require "pg"
require "json" 
require "db"
require "../models"

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
      shards = [] of CrystalShared::Shard
      @db.query(
        "SELECT id, name, description, github_url, homepage_url, documentation_url,
         license, latest_version, download_count, stars, forks, last_activity, tags,
         crystal_versions, dependencies, published, featured, created_at, updated_at,
         ts_rank(to_tsvector('english', name || ' ' || COALESCE(description, '')), 
                 plainto_tsquery('english', $1)) as rank
         FROM shards 
         WHERE published = TRUE 
         AND (to_tsvector('english', name || ' ' || COALESCE(description, '')) @@ plainto_tsquery('english', $1)
              OR name ILIKE '%' || $1 || '%')
         ORDER BY rank DESC, stars DESC
         OFFSET $2 LIMIT $3", query, offset, limit
      ) do |rs|
        rs.each do
          shards << build_shard_from_result_set(rs, has_rank: true)
        end
      end
      shards
    end
    
    def count_published : Int32
      @db.scalar("SELECT COUNT(*) FROM shards WHERE published = TRUE").as(Int64).to_i32
    end
    
    def count_search(query : String) : Int32
      @db.scalar(
        "SELECT COUNT(*) FROM shards 
         WHERE published = TRUE 
         AND (to_tsvector('english', name || ' ' || COALESCE(description, '')) @@ plainto_tsquery('english', $1)
              OR name ILIKE '%' || $1 || '%')", query
      ).as(Int64).to_i32
    end
    
    def update_github_stats(id : Int32, stars : Int32, forks : Int32, last_activity : Time?) : Bool
      @db.exec(
        "UPDATE shards SET stars = $1, forks = $2, last_activity = $3, updated_at = $4 
         WHERE id = $5", stars, forks, last_activity, Time.utc, id
      )
      true
    rescue
      false
    end
    
    def publish(id : Int32) : Bool
      @db.exec("UPDATE shards SET published = TRUE, updated_at = $1 WHERE id = $2", Time.utc, id)
      true
    rescue
      false
    end
    
    def unpublish(id : Int32) : Bool
      @db.exec("UPDATE shards SET published = FALSE, updated_at = $1 WHERE id = $2", Time.utc, id)
      true
    rescue
      false
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