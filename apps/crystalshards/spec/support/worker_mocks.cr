# Mock helpers for worker tests
# These mocks prevent external dependencies during testing

# Mock provider for testing IndexShardWorker
class MockProvider < BaseProvider
  property shard_yml_content : YAML::Any?
  property metadata : RepositoryMetadata?
  property should_fail : Bool = false
  property api_support : Bool = false

  def initialize(@repository_url : String)
    @shard_yml_content = nil
    @metadata = nil
  end

  def fetch_shard_yml(version : String?) : YAML::Any?
    return nil if should_fail
    shard_yml_content
  end

  def fetch_metadata : RepositoryMetadata?
    return nil if should_fail
    metadata
  end

  def clone_repository(target_dir : String) : Bool
    !should_fail
  end

  def checkout_version(repo_dir : String, version : String) : Bool
    !should_fail
  end

  def supports_api? : Bool
    api_support
  end
end

# Mock ProviderFactory for testing
class MockProviderFactory
  @@provider : MockProvider?

  def self.set_provider(provider : MockProvider)
    @@provider = provider
  end

  def self.create(repository_url : String) : BaseProvider
    @@provider || MockProvider.new(repository_url)
  end

  def self.reset
    @@provider = nil
  end
end

# Mock StorageService for testing BuildDocsWorker
module CrystalShards
  class MockStorageService
    property uploaded_docs : Array(String) = [] of String
    property should_fail : Bool = false

    def upload_docs(shard_name : String, version : String, docs_dir : String) : Array(String)
      raise "Storage upload failed" if should_fail

      # Simulate uploaded files
      files = Dir.glob("#{docs_dir}/**/*").reject { |f| File.directory?(f) }
      @uploaded_docs = files.map do |file|
        relative = file.sub("#{docs_dir}/", "")
        "#{shard_name}/#{version}/#{relative}"
      end
      @uploaded_docs
    end
  end
end

# Helper to stub system commands for git operations
class GitCommandStub
  @@commands = {} of String => Int32

  def self.stub(command_pattern : String, exit_code : Int32)
    @@commands[command_pattern] = exit_code
  end

  def self.check(command : String) : Int32?
    @@commands.each do |pattern, code|
      return code if command.includes?(pattern)
    end
    nil
  end

  def self.reset
    @@commands.clear
  end
end

# Mock for JoobQ worker enqueuing to track worker chaining
module WorkerEnqueueTracker
  @@enqueued_workers = [] of Hash(String, String)

  def self.track(worker_name : String, params : Hash(String, String))
    @@enqueued_workers << {"worker" => worker_name}.merge(params)
  end

  def self.enqueued_workers
    @@enqueued_workers
  end

  def self.reset
    @@enqueued_workers.clear
  end

  def self.enqueued?(worker_name : String) : Bool
    @@enqueued_workers.any? { |w| w["worker"] == worker_name }
  end
end
