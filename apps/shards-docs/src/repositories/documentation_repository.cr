require "db"
require "pg"

module CrystalDocs
  # Repository for managing documentation records
  class DocumentationRepository
    
    # Create a new documentation record
    def self.create(shard_id : Int32, version : String, content_path : String) : Int64?
      begin
        result = CrystalDocs::DB.query_one(
          "INSERT INTO documentation (shard_id, version, content_path, build_status) VALUES ($1, $2, $3, 'pending') RETURNING id",
          shard_id, version, content_path
        )
        result.as(Int64)
      rescue ex : PG::PQError
        if ex.message && ex.message.not_nil!.includes?("duplicate key")
          puts "Documentation for shard_id #{shard_id}, version #{version} already exists"
          find_by_shard_and_version(shard_id, version).try &.["id"].as(Int64)
        else
          puts "Error creating documentation: #{ex.message}"
          nil
        end
      rescue ex : Exception
        puts "Error creating documentation: #{ex.message}"
        nil
      end
    end
    
    # Find documentation by shard ID and version
    def self.find_by_shard_and_version(shard_id : Int32, version : String)
      begin
        CrystalDocs::DB.query_one(
          "SELECT id, shard_id, version, content_path, build_status, build_log, file_count, size_bytes, created_at, updated_at FROM documentation WHERE shard_id = $1 AND version = $2",
          shard_id, version
        ) do |rs|
          {
            "id" => rs.read(Int64),
            "shard_id" => rs.read(Int32),
            "version" => rs.read(String),
            "content_path" => rs.read(String),
            "build_status" => rs.read(String),
            "build_log" => rs.read(String?),
            "file_count" => rs.read(Int32),
            "size_bytes" => rs.read(Int64),
            "created_at" => rs.read(Time),
            "updated_at" => rs.read(Time)
          }
        end
      rescue DB::NoResultsError
        nil
      rescue ex : Exception
        puts "Error finding documentation: #{ex.message}"
        nil
      end
    end
    
    # Find documentation by content path
    def self.find_by_content_path(content_path : String)
      begin
        CrystalDocs::DB.query_one(
          "SELECT d.id, d.shard_id, d.version, d.content_path, d.build_status, d.build_log, d.file_count, d.size_bytes, d.created_at, d.updated_at, s.name as shard_name, s.github_repo FROM documentation d JOIN shards s ON d.shard_id = s.id WHERE d.content_path = $1",
          content_path
        ) do |rs|
          {
            "id" => rs.read(Int64),
            "shard_id" => rs.read(Int32),
            "version" => rs.read(String),
            "content_path" => rs.read(String),
            "build_status" => rs.read(String),
            "build_log" => rs.read(String?),
            "file_count" => rs.read(Int32),
            "size_bytes" => rs.read(Int64),
            "created_at" => rs.read(Time),
            "updated_at" => rs.read(Time),
            "shard_name" => rs.read(String),
            "github_repo" => rs.read(String)
          }
        end
      rescue DB::NoResultsError
        nil
      rescue ex : Exception
        puts "Error finding documentation by content path: #{ex.message}"
        nil
      end
    end
    
    # List all documentation for a shard
    def self.list_by_shard_id(shard_id : Int32)
      results = [] of Hash(String, DB::Any)
      
      begin
        CrystalDocs::DB.query(
          "SELECT id, shard_id, version, content_path, build_status, build_log, file_count, size_bytes, created_at, updated_at FROM documentation WHERE shard_id = $1 ORDER BY created_at DESC",
          shard_id
        ) do |rs|
          rs.each do
            results << {
              "id" => rs.read(Int64),
              "shard_id" => rs.read(Int32),
              "version" => rs.read(String),
              "content_path" => rs.read(String),
              "build_status" => rs.read(String),
              "build_log" => rs.read(String?),
              "file_count" => rs.read(Int32),
              "size_bytes" => rs.read(Int64),
              "created_at" => rs.read(Time),
              "updated_at" => rs.read(Time)
            }
          end
        end
      rescue ex : Exception
        puts "Error listing documentation: #{ex.message}"
      end
      
      results
    end
    
    # List recent documentation builds
    def self.list_recent(limit = 50)
      results = [] of Hash(String, DB::Any)
      
      begin
        CrystalDocs::DB.query(
          "SELECT d.id, d.shard_id, d.version, d.content_path, d.build_status, d.build_log, d.file_count, d.size_bytes, d.created_at, d.updated_at, s.name as shard_name, s.github_repo FROM documentation d JOIN shards s ON d.shard_id = s.id ORDER BY d.created_at DESC LIMIT $1",
          limit
        ) do |rs|
          rs.each do
            results << {
              "id" => rs.read(Int64),
              "shard_id" => rs.read(Int32),
              "version" => rs.read(String),
              "content_path" => rs.read(String),
              "build_status" => rs.read(String),
              "build_log" => rs.read(String?),
              "file_count" => rs.read(Int32),
              "size_bytes" => rs.read(Int64),
              "created_at" => rs.read(Time),
              "updated_at" => rs.read(Time),
              "shard_name" => rs.read(String),
              "github_repo" => rs.read(String)
            }
          end
        end
      rescue ex : Exception
        puts "Error listing recent documentation: #{ex.message}"
      end
      
      results
    end
    
    # Update build status
    def self.update_build_status(id : Int64, status : String, log : String? = nil, file_count : Int32? = nil, size_bytes : Int64? = nil)
      begin
        if file_count && size_bytes
          CrystalDocs::DB.exec(
            "UPDATE documentation SET build_status = $1, build_log = $2, file_count = $3, size_bytes = $4, updated_at = NOW() WHERE id = $5",
            status, log, file_count, size_bytes, id
          )
        else
          CrystalDocs::DB.exec(
            "UPDATE documentation SET build_status = $1, build_log = $2, updated_at = NOW() WHERE id = $3",
            status, log, id
          )
        end
        true
      rescue ex : Exception
        puts "Error updating build status: #{ex.message}"
        false
      end
    end
    
    # Update build status by content path
    def self.update_build_status_by_path(content_path : String, status : String, log : String? = nil)
      begin
        CrystalDocs::DB.exec(
          "UPDATE documentation SET build_status = $1, build_log = $2, updated_at = NOW() WHERE content_path = $3",
          status, log, content_path
        )
        true
      rescue ex : Exception
        puts "Error updating build status by path: #{ex.message}"
        false
      end
    end
    
    # Delete documentation record
    def self.delete(id : Int64)
      begin
        CrystalDocs::DB.exec("DELETE FROM documentation WHERE id = $1", id)
        true
      rescue ex : Exception
        puts "Error deleting documentation: #{ex.message}"
        false
      end
    end
    
    # Get build statistics
    def self.get_build_stats
      begin
        CrystalDocs::DB.query_one(
          "SELECT 
            COUNT(*) as total_builds,
            COUNT(*) FILTER (WHERE build_status = 'success') as successful_builds,
            COUNT(*) FILTER (WHERE build_status = 'failed') as failed_builds,
            COUNT(*) FILTER (WHERE build_status = 'building') as building,
            COUNT(*) FILTER (WHERE build_status = 'pending') as pending,
            COALESCE(AVG(file_count) FILTER (WHERE build_status = 'success'), 0) as avg_file_count,
            COALESCE(AVG(size_bytes) FILTER (WHERE build_status = 'success'), 0) as avg_size_bytes
          FROM documentation"
        ) do |rs|
          {
            "total_builds" => rs.read(Int64),
            "successful_builds" => rs.read(Int64),
            "failed_builds" => rs.read(Int64),
            "building" => rs.read(Int64),
            "pending" => rs.read(Int64),
            "avg_file_count" => rs.read(Float64),
            "avg_size_bytes" => rs.read(Float64)
          }
        end
      rescue ex : Exception
        puts "Error getting build stats: #{ex.message}"
        {
          "total_builds" => 0_i64,
          "successful_builds" => 0_i64,
          "failed_builds" => 0_i64,
          "building" => 0_i64,
          "pending" => 0_i64,
          "avg_file_count" => 0.0,
          "avg_size_bytes" => 0.0
        }
      end
    end
    
    # Search documentation by shard name or version
    def self.search(query : String, limit = 20)
      results = [] of Hash(String, DB::Any)
      search_term = "%#{query}%"
      
      begin
        CrystalDocs::DB.query(
          "SELECT d.id, d.shard_id, d.version, d.content_path, d.build_status, d.file_count, d.size_bytes, d.created_at, d.updated_at, s.name as shard_name, s.description, s.github_repo 
           FROM documentation d 
           JOIN shards s ON d.shard_id = s.id 
           WHERE d.build_status = 'success' 
           AND (s.name ILIKE $1 OR s.description ILIKE $1 OR d.version ILIKE $1)
           ORDER BY s.name, d.created_at DESC 
           LIMIT $2",
          search_term, limit
        ) do |rs|
          rs.each do
            results << {
              "id" => rs.read(Int64),
              "shard_id" => rs.read(Int32),
              "version" => rs.read(String),
              "content_path" => rs.read(String),
              "build_status" => rs.read(String),
              "file_count" => rs.read(Int32),
              "size_bytes" => rs.read(Int64),
              "created_at" => rs.read(Time),
              "updated_at" => rs.read(Time),
              "shard_name" => rs.read(String),
              "description" => rs.read(String?),
              "github_repo" => rs.read(String)
            }
          end
        end
      rescue ex : Exception
        puts "Error searching documentation: #{ex.message}"
      end
      
      results
    end
  end
end