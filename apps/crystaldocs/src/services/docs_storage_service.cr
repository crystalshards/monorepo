require "../../config/minio"

module CrystalDocs
  # Service for fetching documentation from MinIO object storage
  class DocsStorageService
    def initialize
      @client = MinIOConfig.client
    end

    # Download a documentation file from MinIO
    def fetch_doc_file(package_name : String, version : String, file_path : String) : String?
      key = docs_key(package_name, version, file_path)
      begin
        response = @client.get_object(
          bucket: MinIOConfig.settings.docs_bucket,
          key: key
        )
        response.body
      rescue ex : Awscr::S3::Exception
        nil
      end
    end

    # List all files in a documentation version
    def list_doc_files(package_name : String, version : String) : Array(String)
      prefix = "#{package_name}/#{version}/"
      files = [] of String

      begin
        response = @client.list_objects(
          bucket: MinIOConfig.settings.docs_bucket,
          prefix: prefix
        )

        response.contents.each do |object|
          files << object.key.sub(prefix, "")
        end
      rescue ex : Awscr::S3::Exception
        # Return empty array if listing fails
      end

      files
    end

    # Check if documentation exists for a package version
    def docs_exist?(package_name : String, version : String) : Bool
      key = docs_key(package_name, version, "index.html")
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

    # Get the index.html for a documentation version
    def fetch_index(package_name : String, version : String) : String?
      fetch_doc_file(package_name, version, "index.html")
    end

    # Generate presigned URL for direct access to a documentation file
    def presigned_url(package_name : String, version : String, file_path : String, expires_in : Time::Span = 1.hour) : String
      key = docs_key(package_name, version, file_path)

      options = Awscr::S3::Presigned::Url::Options.new(
        aws_access_key: MinIOConfig.settings.access_key,
        aws_secret_key: MinIOConfig.settings.secret_key,
        region: MinIOConfig.settings.region,
        object: key,
        bucket: MinIOConfig.settings.docs_bucket
      )

      url = Awscr::S3::Presigned::Url.new(options)
      url.for(:get)
    end

    private def docs_key(package_name : String, version : String, file_path : String) : String
      "#{package_name}/#{version}/#{file_path}"
    end
  end
end
