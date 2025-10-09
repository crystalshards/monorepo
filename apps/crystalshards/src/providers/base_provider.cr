abstract class BaseProvider
  getter repository_url : String

  def initialize(@repository_url : String)
  end

  abstract def fetch_shard_yml(version : String?) : YAML::Any?
  abstract def fetch_metadata : RepositoryMetadata?
  abstract def clone_repository(target_dir : String) : Bool
  abstract def checkout_version(repo_dir : String, version : String) : Bool

  def extract_repo_path : String?
    nil
  end

  def supports_api? : Bool
    false
  end

  class RepositoryMetadata
    property stars : Int32?
    property forks : Int32?
    property description : String?
    property homepage : String?
    property default_branch : String?
    property latest_commit_sha : String?

    def initialize(
      @stars = nil,
      @forks = nil,
      @description = nil,
      @homepage = nil,
      @default_branch = nil,
      @latest_commit_sha = nil
    )
    end
  end
end
