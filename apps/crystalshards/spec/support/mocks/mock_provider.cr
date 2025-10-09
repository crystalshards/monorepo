require "../../../src/providers/base_provider"

class MockProvider < BaseProvider
  property! shard_yml_content : String?
  property! metadata : RepositoryMetadata?
  property simulate_fetch_error : Bool = false
  property simulate_metadata_error : Bool = false
  property fetch_shard_yml_calls = [] of String
  property fetch_metadata_calls = 0

  def initialize(@repository_url : String, @shard_yml_content = nil, @metadata = nil)
  end

  def fetch_shard_yml(version : String?) : YAML::Any?
    fetch_shard_yml_calls << version.to_s
    return nil if simulate_fetch_error
    content = @shard_yml_content
    return nil unless content

    YAML.parse(content)
  rescue ex : YAML::ParseException
    nil
  end

  def fetch_metadata : RepositoryMetadata?
    @fetch_metadata_calls += 1
    return nil if simulate_metadata_error
    @metadata
  end

  def clone_repository(target_dir : String) : Bool
    true
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    true
  end

  def supports_api? : Bool
    !@metadata.nil?
  end

  def provider_name : String
    "mock"
  end

  def repository_type : String
    "git"
  end
end
