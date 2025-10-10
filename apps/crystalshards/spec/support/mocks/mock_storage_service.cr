require "../../../src/services/base_storage_service"

module CrystalShards
  class MockStorageService
    include BaseStorageService

    property uploaded_docs = {} of String => Array(String)
    property uploaded_packages = {} of String => String
    property simulate_upload_error : Bool = false
    property upload_docs_calls = [] of {String, String, String}

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

    def reset
      @uploaded_docs.clear
      @uploaded_packages.clear
      @upload_docs_calls.clear
      @simulate_upload_error = false
    end
  end
end
