require "awscr-s3"

module CrystalShards
  # MinIO configuration for object storage
  # Used for storing packages (.tar.gz) and documentation (HTML)
  class MinIOConfig
    Habitat.create do
      setting endpoint : String
      setting access_key : String
      setting secret_key : String
      setting region : String = "us-east-1"
      setting packages_bucket : String = "packages"
      setting docs_bucket : String = "docs"
      setting use_ssl : Bool = true
    end

    def self.client
      Awscr::S3::Client.new(
        region: settings.region,
        aws_access_key: settings.access_key,
        aws_secret_key: settings.secret_key,
        endpoint: settings.endpoint
      )
    end
  end
end

# Configure MinIO from environment variables
CrystalShards::MinIOConfig.configure do |config|
  config.endpoint = ENV.fetch("MINIO_ENDPOINT", "minio.infrastructure.svc.cluster.local:9000")
  config.access_key = ENV.fetch("MINIO_ACCESS_KEY", "minioadmin")
  config.secret_key = ENV.fetch("MINIO_SECRET_KEY", "minioadmin")
  config.region = ENV.fetch("MINIO_REGION", "us-east-1")
  config.packages_bucket = ENV.fetch("MINIO_PACKAGES_BUCKET", "packages")
  config.docs_bucket = ENV.fetch("MINIO_DOCS_BUCKET", "docs")
  config.use_ssl = ENV.fetch("MINIO_USE_SSL", "false") == "true"
end
