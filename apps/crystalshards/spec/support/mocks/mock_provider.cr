require "../../../src/providers/base_provider"

class MockProvider < BaseProvider
  property shard_yml_content : String?
  property metadata_result : RepositoryMetadata?
  property clone_success : Bool = true
  property checkout_success : Bool = true
  property should_raise : Exception?

  def fetch_shard_yml(version : String? = nil) : YAML::Any?
    if ex = should_raise
      raise ex
    end
    return nil unless shard_yml_content
    YAML.parse(shard_yml_content.not_nil!)
  end

  def fetch_metadata : RepositoryMetadata?
    if ex = should_raise
      raise ex
    end
    metadata_result
  end

  def clone_repository(target_dir : String) : Bool
    if ex = should_raise
      raise ex
    end
    clone_success
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    if ex = should_raise
      raise ex
    end
    checkout_success
  end

  def supports_api? : Bool
    !metadata_result.nil?
  end

  def extract_repo_path : String?
    "test/repo"
  end
end
