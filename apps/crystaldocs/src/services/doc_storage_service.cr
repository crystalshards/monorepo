require "http/client"
require "json"

module CrystalDocs
  # Service for managing documentation storage in MinIO
  class DocStorageService
    MINIO_HOST = ENV["MINIO_HOST"]? || "minio.infrastructure.svc.cluster.local:9000"
    MINIO_ACCESS_KEY = ENV["MINIO_ACCESS_KEY"]? || "minioadmin"
    MINIO_SECRET_KEY = ENV["MINIO_SECRET_KEY"]? || "minioadmin123"
    BUCKET_NAME = "documentation"
    
    # Check if documentation exists for given content path
    def self.documentation_exists?(content_path : String) : Bool
      begin
        response = minio_request("HEAD", "/#{BUCKET_NAME}/#{content_path}/index.html")
        response.status_code == 200
      rescue ex : Exception
        puts "Error checking documentation existence: #{ex.message}"
        false
      end
    end
    
    # Get documentation file content
    def self.get_documentation_file(content_path : String, file_path : String = "index.html") : String?
      begin
        response = minio_request("GET", "/#{BUCKET_NAME}/#{content_path}/#{file_path}")
        
        if response.status_code == 200
          response.body
        else
          nil
        end
      rescue ex : Exception
        puts "Error fetching documentation file: #{ex.message}"
        nil
      end
    end
    
    # List files in documentation directory
    def self.list_documentation_files(content_path : String) : Array(String)
      begin
        response = minio_request("GET", "/#{BUCKET_NAME}?prefix=#{content_path}/&delimiter=/")
        
        if response.status_code == 200
          # Parse XML response to extract file names
          # This is a simplified parser - in production would use proper XML library
          files = [] of String
          response.body.scan(/<Key>([^<]+)<\/Key>/) do |match|
            file_path = match[1].as(String)
            if file_path.starts_with?("#{content_path}/")
              files << file_path.sub("#{content_path}/", "")
            end
          end
          files
        else
          [] of String
        end
      rescue ex : Exception
        puts "Error listing documentation files: #{ex.message}"
        [] of String
      end
    end
    
    # Get documentation metadata (file count, total size)
    def self.get_documentation_metadata(content_path : String)
      begin
        response = minio_request("GET", "/#{BUCKET_NAME}?prefix=#{content_path}/")
        
        if response.status_code == 200
          file_count = 0
          total_size = 0_i64
          
          response.body.scan(/<Size>(\d+)<\/Size>/) do |match|
            total_size += match[1].as(String).to_i64
            file_count += 1
          end
          
          {
            file_count: file_count,
            total_size: total_size
          }
        else
          {
            file_count: 0,
            total_size: 0_i64
          }
        end
      rescue ex : Exception
        puts "Error getting documentation metadata: #{ex.message}"
        {
          file_count: 0,
          total_size: 0_i64
        }
      end
    end
    
    # Upload documentation file (used by build process)
    def self.upload_documentation_file(content_path : String, file_path : String, content : String) : Bool
      begin
        response = minio_request("PUT", "/#{BUCKET_NAME}/#{content_path}/#{file_path}", content)
        response.status_code == 200
      rescue ex : Exception
        puts "Error uploading documentation file: #{ex.message}"
        false
      end
    end
    
    # Delete documentation directory
    def self.delete_documentation(content_path : String) : Bool
      begin
        # List all files in the directory first
        files = list_documentation_files(content_path)
        
        # Delete each file
        files.each do |file|
          minio_request("DELETE", "/#{BUCKET_NAME}/#{content_path}/#{file}")
        end
        
        true
      rescue ex : Exception
        puts "Error deleting documentation: #{ex.message}"
        false
      end
    end
    
    # Generate public URL for documentation
    def self.get_documentation_url(content_path : String, file_path : String = "index.html") : String
      if MINIO_HOST.includes?("localhost") || MINIO_HOST.includes?("127.0.0.1")
        "http://#{MINIO_HOST}/#{BUCKET_NAME}/#{content_path}/#{file_path}"
      else
        "https://docs.crystalshards.org/#{content_path}/#{file_path}"
      end
    end
    
    # Create presigned URL for temporary access (for development/debugging)
    def self.create_presigned_url(content_path : String, file_path : String = "index.html", expires_in_hours = 1) : String?
      begin
        # For MinIO, we would normally use AWS SDK to create presigned URLs
        # For now, return direct URL
        get_documentation_url(content_path, file_path)
      rescue ex : Exception
        puts "Error creating presigned URL: #{ex.message}"
        nil
      end
    end
    
    # Health check for MinIO connection
    def self.health_check : Bool
      begin
        response = minio_request("GET", "/")
        response.status_code == 200 || response.status_code == 403 # 403 is normal for root path
      rescue ex : Exception
        puts "MinIO health check failed: #{ex.message}"
        false
      end
    end
    
    # Get storage usage statistics
    def self.get_storage_stats
      begin
        response = minio_request("GET", "/#{BUCKET_NAME}")
        
        if response.status_code == 200
          total_files = 0
          total_size = 0_i64
          
          response.body.scan(/<Size>(\d+)<\/Size>/) do |match|
            total_size += match[1].as(String).to_i64
            total_files += 1
          end
          
          {
            bucket_name: BUCKET_NAME,
            total_files: total_files,
            total_size_bytes: total_size,
            total_size_mb: (total_size / 1024 / 1024).to_f.round(2),
            accessible: true
          }
        else
          {
            bucket_name: BUCKET_NAME,
            total_files: 0,
            total_size_bytes: 0_i64,
            total_size_mb: 0.0,
            accessible: false,
            error: "Bucket not accessible"
          }
        end
      rescue ex : Exception
        {
          bucket_name: BUCKET_NAME,
          total_files: 0,
          total_size_bytes: 0_i64,
          total_size_mb: 0.0,
          accessible: false,
          error: ex.message
        }
      end
    end
    
    private def self.minio_request(method : String, path : String, body : String? = nil) : HTTP::Client::Response
      url = "http://#{MINIO_HOST}#{path}"
      uri = URI.parse(url)
      
      client = HTTP::Client.new(uri.host.not_nil!, uri.port)
      
      headers = HTTP::Headers.new
      headers["Host"] = uri.host.not_nil!
      
      # Add authentication if credentials are provided
      if MINIO_ACCESS_KEY != "minioadmin" || MINIO_SECRET_KEY != "minioadmin123"
        # In production, this should use proper AWS Signature Version 4
        # For development, we'll use basic auth or assume public access
        headers["Authorization"] = "AWS #{MINIO_ACCESS_KEY}:#{MINIO_SECRET_KEY}"
      end
      
      if body
        headers["Content-Type"] = "text/html"
        headers["Content-Length"] = body.bytesize.to_s
      end
      
      case method.upcase
      when "GET"
        client.get(uri.path.not_nil!, headers: headers)
      when "HEAD"
        client.head(uri.path.not_nil!, headers: headers)
      when "PUT"
        client.put(uri.path.not_nil!, headers: headers, body: body)
      when "DELETE"
        client.delete(uri.path.not_nil!, headers: headers)
      else
        raise "Unsupported HTTP method: #{method}"
      end
    end
  end
end