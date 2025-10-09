require "../../../src/services/storage_service"

module CrystalShards
  class MockStorageService < StorageService
    property uploaded_docs = {} of String => Array(String)
    property uploaded_packages = {} of String => String
    property simulate_upload_error : Bool = false
    property upload_docs_calls = [] of {String, String, String}

    def initialize
      # Don't call super - we don't need the real MinIO client
      # Set @client to uninitialized since we won't use it in the mock
      @client = uninitialized Awscr::S3::Client
    end

    def upload_docs(shard_name : String, version : String, docs_dir : String) : Array(String)
      upload_docs_calls << {shard_name, version, docs_dir}

      if simulate_upload_error
        raise Exception.new("MinIO upload failed")
      end

      keys = ["#{shard_name}/#{version}/index.html"]
      uploaded_docs["#{shard_name}/#{version}"] = keys
      keys
    end

    def upload_package(shard_name : String, version : String, file_path : String) : String
      if simulate_upload_error
        raise Exception.new("MinIO upload failed")
      end

      key = "#{shard_name}/#{version}/#{shard_name}-#{version}.tar.gz"
      uploaded_packages[key] = file_path
      key
    end

    def upload_package_from_io(shard_name : String, version : String, content : String) : String
      if simulate_upload_error
        raise Exception.new("MinIO upload failed")
      end

      key = "#{shard_name}/#{version}/#{shard_name}-#{version}.tar.gz"
      uploaded_packages[key] = content
      key
    end

    def package_exists?(shard_name : String, version : String) : Bool
      key = "#{shard_name}/#{version}/#{shard_name}-#{version}.tar.gz"
      uploaded_packages.has_key?(key)
    end

    def docs_exist?(shard_name : String, version : String) : Bool
      uploaded_docs.has_key?("#{shard_name}/#{version}")
    end

    def download_package(shard_name : String, version : String) : String
      key = "#{shard_name}/#{version}/#{shard_name}-#{version}.tar.gz"
      uploaded_packages[key]? || raise Exception.new("Package not found")
    end

    def download_doc(shard_name : String, version : String, file_path : String) : String
      "Mock doc content for #{shard_name}/#{version}/#{file_path}"
    end

    def package_download_url(shard_name : String, version : String, expires_in : Time::Span = 1.hour) : String
      "https://mock-storage.local/#{shard_name}/#{version}/#{shard_name}-#{version}.tar.gz"
    end

    def reset
      @uploaded_docs.clear
      @uploaded_packages.clear
      @upload_docs_calls.clear
      @simulate_upload_error = false
    end
  end
end
