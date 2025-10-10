module CrystalShards
  class MockStorageService
    property uploaded_docs : Hash(String, Array(String)) = {} of String => Array(String)
    property should_raise : Exception?
    property upload_docs_result : Array(String) = [] of String

    def upload_docs(shard_name : String, version : String, docs_dir : String) : Array(String)
      raise should_raise if should_raise

      key = "#{shard_name}/#{version}"
      uploaded_docs[key] = upload_docs_result
      upload_docs_result
    end

    def upload_package(shard_name : String, version : String, file_path : String) : String
      raise should_raise if should_raise
      "#{shard_name}/#{version}/package.tar.gz"
    end

    def package_exists?(shard_name : String, version : String) : Bool
      true
    end

    def docs_exist?(shard_name : String, version : String) : Bool
      key = "#{shard_name}/#{version}"
      uploaded_docs.has_key?(key)
    end
  end
end
