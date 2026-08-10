# Fakes for worker specs. Each one plugs into a `class_property` seam on the
# collaborator it stands in for, so workers can be exercised with no network,
# no git and no Redis.

# Stands in for a real repository provider behind `ProviderFactory.builder`.
class MockProvider < BaseProvider
  property shard_yml_content : YAML::Any?
  property metadata : RepositoryMetadata?
  property readme_content : String?
  property should_fail : Bool = false
  property api_support : Bool = false

  def initialize(@repository_url : String)
    @shard_yml_content = nil
    @metadata = nil
    @readme_content = nil
  end

  def fetch_shard_yml(version : String?) : YAML::Any?
    return nil if should_fail
    shard_yml_content
  end

  def fetch_metadata : RepositoryMetadata?
    return nil if should_fail
    metadata
  end

  def fetch_readme(version : String? = nil) : String?
    return nil if should_fail
    readme_content
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

# Stands in for MinIO behind `CrystalShards::StorageService.builder`.
module CrystalShards
  class MockStorageService
    include DocsStorage

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

  # Stands in for git/shards/crystal behind `CrystalShards::DocsBuilder.builder`.
  #
  # Records the arguments it was handed and writes `docs_files` into the work
  # directory. Set `should_fail` to model a `crystal docs` run that produced
  # nothing, or `raise_with` to model a clone that blew up.
  class MockDocsBuilder < DocsBuilder
    record Call, repository_url : String, version : String, commit_sha : String?, work_dir : String

    property calls : Array(Call) = [] of Call
    property docs_files : Hash(String, String) = {"index.html" => "<html>docs</html>"}
    property should_fail : Bool = false
    property raise_with : String? = nil

    def generate_docs(repository_url : String, version : String, commit_sha : String?, work_dir : String) : String?
      @calls << Call.new(repository_url, version, commit_sha, work_dir)

      if message = raise_with
        raise message
      end

      return nil if should_fail

      docs_dir = File.join(work_dir, "docs")
      Dir.mkdir_p(docs_dir)
      docs_files.each do |name, contents|
        File.write(File.join(docs_dir, name), contents)
      end
      docs_dir
    end
  end
end

# Installs the fakes on their seams for the duration of the block and always
# restores the production defaults afterwards, so no state leaks between
# examples.
module WorkerSeams
  def self.with_provider(provider : BaseProvider, &)
    ProviderFactory.builder = ->(_url : String) { provider.as(BaseProvider) }
    begin
      yield
    ensure
      ProviderFactory.builder = nil
    end
  end

  def self.with_docs_pipeline(
    docs_builder : CrystalShards::MockDocsBuilder,
    storage : CrystalShards::MockStorageService,
    &
  )
    CrystalShards::DocsBuilder.builder = -> { docs_builder.as(CrystalShards::DocsBuilder) }
    CrystalShards::StorageService.builder = -> { storage.as(CrystalShards::DocsStorage) }
    begin
      yield
    ensure
      CrystalShards::DocsBuilder.builder = nil
      CrystalShards::StorageService.builder = nil
    end
  end

  # Captures the follow-up jobs IndexShardWorker schedules instead of pushing
  # them onto the JoobQ queue, which needs a Redis connection specs do not have.
  def self.capturing_followups(&)
    captured = [] of {IndexShardWorker::Followup, String, String}
    original = IndexShardWorker.dispatcher

    IndexShardWorker.dispatcher = ->(followup : IndexShardWorker::Followup, shard_name : String, version : String) {
      captured << {followup, shard_name, version}
      nil
    }

    begin
      yield captured
    ensure
      IndexShardWorker.dispatcher = original
    end
  end
end
