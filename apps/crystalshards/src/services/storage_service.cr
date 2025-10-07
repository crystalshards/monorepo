require "../../config/minio"

module CrystalShards
  # Service for interacting with MinIO object storage
  # Handles package and documentation storage
  class StorageService
    def initialize
      @client = MinIOConfig.client
    end

    # Upload a package file to MinIO
    # Returns the object key (path in MinIO)
    def upload_package(shard_name : String, version : String, file_path : String) : String
      key = package_key(shard_name, version)

      File.open(file_path, "r") do |file|
        @client.put_object(
          bucket: MinIOConfig.settings.packages_bucket,
          key: key,
          body: file.gets_to_end,
          metadata: HTTP::Headers{
            "Content-Type"    => "application/gzip",
            "X-Shard-Name"    => shard_name,
            "X-Shard-Version" => version,
          }
        )
      end

      key
    end

    # Download a package file from MinIO
    # Returns the file contents as a String
    def download_package(shard_name : String, version : String) : String
      key = package_key(shard_name, version)
      response = @client.get_object(
        bucket: MinIOConfig.settings.packages_bucket,
        key: key
      )
      response.body
    end

    # Check if a package exists in MinIO
    def package_exists?(shard_name : String, version : String) : Bool
      key = package_key(shard_name, version)
      begin
        @client.head_object(
          bucket: MinIOConfig.settings.packages_bucket,
          key: key
        )
        true
      rescue ex : Awscr::S3::Exception
        false
      end
    end

    # Upload documentation files to MinIO
    # Uploads all HTML files from a directory
    def upload_docs(shard_name : String, version : String, docs_dir : String) : Array(String)
      uploaded_keys = [] of String

      Dir.glob("#{docs_dir}/**/*") do |file_path|
        next if File.directory?(file_path)

        relative_path = file_path.sub("#{docs_dir}/", "")
        key = docs_key(shard_name, version, relative_path)

        content_type = case File.extname(file_path)
                       when ".html" then "text/html"
                       when ".css"  then "text/css"
                       when ".js"   then "application/javascript"
                       when ".json" then "application/json"
                       else              "application/octet-stream"
                       end

        File.open(file_path, "r") do |file|
          @client.put_object(
            bucket: MinIOConfig.settings.docs_bucket,
            key: key,
            body: file.gets_to_end,
            metadata: HTTP::Headers{
              "Content-Type"    => content_type,
              "X-Shard-Name"    => shard_name,
              "X-Shard-Version" => version,
            }
          )
        end

        uploaded_keys << key
      end

      uploaded_keys
    end

    # Get documentation file from MinIO
    def download_doc(shard_name : String, version : String, file_path : String) : String
      key = docs_key(shard_name, version, file_path)
      response = @client.get_object(
        bucket: MinIOConfig.settings.docs_bucket,
        key: key
      )
      response.body
    end

    # Check if documentation exists for a shard version
    def docs_exist?(shard_name : String, version : String) : Bool
      key = docs_key(shard_name, version, "index.html")
      begin
        @client.head_object(
          bucket: MinIOConfig.settings.docs_bucket,
          key: key
        )
        true
      rescue ex : Awscr::S3::Exception
        false
      end
    end

    # Generate presigned URL for package download
    # Expires in 1 hour by default
    def package_download_url(shard_name : String, version : String, expires_in : Time::Span = 1.hour) : String
      key = package_key(shard_name, version)

      options = Awscr::S3::Presigned::Url::Options.new(
        aws_access_key: MinIOConfig.settings.access_key,
        aws_secret_key: MinIOConfig.settings.secret_key,
        region: MinIOConfig.settings.region,
        object: key,
        bucket: MinIOConfig.settings.packages_bucket
      )

      url = Awscr::S3::Presigned::Url.new(options)
      url.for(:get)
    end

    private def package_key(shard_name : String, version : String) : String
      "#{shard_name}/#{version}/#{shard_name}-#{version}.tar.gz"
    end

    private def docs_key(shard_name : String, version : String, file_path : String) : String
      "#{shard_name}/#{version}/#{file_path}"
    end
  end
end
