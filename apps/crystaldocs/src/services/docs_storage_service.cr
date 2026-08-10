require "../../config/minio"

module CrystalDocs
  # Service for fetching documentation from MinIO object storage
  class DocsStorageService
    # Outcome of a documentation fetch.
    #
    # "MinIO says this file does not exist" and "MinIO never gave us an answer"
    # are different facts. Collapsing both into a bare nil meant a storage
    # outage looked identical to missing documentation, so callers keep the
    # distinction and only tell a reader the docs are gone when they are.
    struct Fetch
      getter content : String?

      def self.found(content : String) : Fetch
        new(content, store_answered: true)
      end

      # MinIO answered, and the file is not in the bucket.
      def self.absent : Fetch
        new(nil, store_answered: true)
      end

      # MinIO could not be reached, or failed for some reason other than a
      # missing object, so whether the documentation exists is unknown.
      def self.unavailable : Fetch
        new(nil, store_answered: false)
      end

      def initialize(@content : String?, @store_answered : Bool)
      end

      def found? : Bool
        !@content.nil?
      end

      # True when "no content" is MinIO's own answer rather than our guess.
      def store_answered? : Bool
        @store_answered
      end
    end

    def initialize
      @client = MinIOConfig.client
    end

    # Download a documentation file from MinIO
    def fetch_doc_file(package_name : String, version : String, file_path : String) : Fetch
      key = docs_key(package_name, version, file_path)

      begin
        response = @client.get_object(
          MinIOConfig.settings.docs_bucket,
          key
        )
        Fetch.found(response.body)
      rescue ex : Awscr::S3::NoSuchKey
        Fetch.absent
      rescue ex : Awscr::S3::Exception | IO::Error
        # Awscr::S3 only wraps error *responses*. An endpoint that is down,
        # unresolvable, or timing out surfaces as a socket error instead, so
        # both have to be handled or the request dies with a 500.
        log_unavailable(key, ex)
        Fetch.unavailable
      end
    end

    # List all files in a documentation version. Empty when MinIO is
    # unreachable, so treat it as "nothing we can show" rather than proof
    # that a version has no files.
    def list_doc_files(package_name : String, version : String) : Array(String)
      prefix = "#{package_name}/#{version}/"
      files = [] of String

      begin
        response = @client.list_objects(
          MinIOConfig.settings.docs_bucket,
          prefix
        )

        response.contents.each do |object|
          files << object.key.sub(prefix, "")
        end
      rescue ex : Awscr::S3::Exception | IO::Error
        log_unavailable(prefix, ex)
      end

      files
    end

    # Check if documentation exists for a package version. False also covers
    # "we could not ask", which is the only honest answer a Bool can carry.
    def docs_exist?(package_name : String, version : String) : Bool
      key = docs_key(package_name, version, "index.html")

      begin
        @client.head_object(
          MinIOConfig.settings.docs_bucket,
          key
        )
        true
      rescue ex : Awscr::S3::NoSuchKey
        false
      rescue ex : Awscr::S3::Exception | IO::Error
        log_unavailable(key, ex)
        false
      end
    end

    # Get the index.html for a documentation version
    def fetch_index(package_name : String, version : String) : Fetch
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

    private def log_unavailable(key : String, error : Exception) : Nil
      Lucky::Log.dexter.warn do
        {docs_storage_unavailable: key, error: error.message}
      end
    end
  end
end
