module CrystalShards
  # Base module for storage services
  # Defines the interface that all storage service implementations must follow
  module BaseStorageService
    abstract def upload_docs(shard_name : String, version : String, docs_dir : String) : Array(String)
    abstract def upload_package(shard_name : String, version : String, file_path : String) : String
    abstract def upload_package_from_io(shard_name : String, version : String, content : String) : String
    abstract def package_exists?(shard_name : String, version : String) : Bool
    abstract def docs_exist?(shard_name : String, version : String) : Bool
  end
end
