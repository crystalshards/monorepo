require "awscr-s3"

module CrystalDocs
  # MinIO configuration for documentation storage
  class MinIOConfig
    class Settings
      property endpoint : String
      property access_key : String
      property secret_key : String
      property region : String
      property docs_bucket : String

      def initialize
        @endpoint = ENV["MINIO_ENDPOINT"]? || "http://minio.infrastructure.svc.cluster.local:9000"
        @access_key = ENV["MINIO_ACCESS_KEY"]
        @secret_key = ENV["MINIO_SECRET_KEY"]
        @region = ENV["MINIO_REGION"]? || "us-east-1"
        @docs_bucket = ENV["MINIO_DOCS_BUCKET"]? || "crystal-docs"
      end
    end

    class_getter settings : Settings = Settings.new

    def self.client : Awscr::S3::Client
      Awscr::S3::Client.new(
        region: settings.region,
        aws_access_key: settings.access_key,
        aws_secret_key: settings.secret_key,
        endpoint: settings.endpoint
      )
    end
  end
end
