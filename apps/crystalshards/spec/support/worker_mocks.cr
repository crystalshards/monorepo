# Fakes for worker specs. Each one plugs into a `class_property` seam on the
# collaborator it stands in for, so workers can be exercised with no network,
# no git and no broker.

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

# Stands in for the object store behind `CrystalShards::StorageService.builder`.
module CrystalShards
  class MockStorageService
    include DocsStorage

    property uploaded_docs : Array(String) = [] of String
    property should_fail : Bool = false

    # Artifacts a previous build published, so a spec can model the state the
    # bucket is actually in for most of the catalogue: the version is already
    # documented and nothing about it can change.
    property existing : Set(String) = Set(String).new

    # The store cannot answer whether an artifact is there, which is a
    # different fact from an empty bucket and takes a different path out of the
    # worker. Kept separate from `should_fail`, which models a failing upload,
    # because a spec has to be able to fail exactly one of the two.
    property stat_unavailable : Bool = false

    def upload_docs_json(shard_name : String, version : String, docs_json_path : String) : String
      raise "Storage upload failed" if should_fail

      key = CrystalStorage::Keys.docs_json(shard_name, version)
      @uploaded_docs << key
      key
    end

    # What was uploaded is there afterwards, the same way it would be in a real
    # store. Without that, a fake would let a second build of one version look
    # like a first.
    def docs_json_exists?(shard_name : String, version : String) : Bool
      key = CrystalStorage::Keys.docs_json(shard_name, version)

      if stat_unavailable
        raise CrystalStorage::Unavailable.new("stat", key, "the fake store was told it could not answer")
      end

      @existing.includes?(key) || @uploaded_docs.includes?(key)
    end
  end

  # Stands in for the object store behind
  # `CrystalShards::StorageService.scratch_builder`, so a sandbox spec runs
  # with no object store at all.
  #
  # `scratch_signed_url` returns a URL that is deliberately not fetchable. The
  # point of the signed-URL seam is that the build receives exactly one URL per
  # object and cannot name its own key, and a fake proves that by recording
  # what was minted, not by serving bytes.
  class MockScratchStorage
    include ScratchStorage

    record Minted, key : String, method : String, content_type : String?

    property objects : Hash(String, String) = {} of String => String
    property minted : Array(Minted) = [] of Minted
    property deleted_prefixes : Array(String) = [] of String

    def upload_scratch(key : String, content : String)
      @objects[key] = content
    end

    def download_scratch(key : String) : String
      @objects[key]? || raise "no scratch object at #{key}"
    end

    def delete_scratch_prefix(prefix : String)
      @deleted_prefixes << prefix
      @objects.reject! { |key, _| key.starts_with?(prefix) }
    end

    def scratch_signed_url(key : String, method : String, content_type : String? = nil) : String
      @minted << Minted.new(key, method.upcase, content_type)
      "https://signed.invalid/#{key}?method=#{method.upcase}"
    end
  end

  # Stands in for git/shards/crystal behind `CrystalShards::DocsBuilder.builder`.
  #
  # Records the arguments it was handed and writes `docs_json` into the work
  # directory as the build's one artifact. Set `should_fail` to model a
  # `crystal docs` run that produced nothing, `raise_with` to model a clone
  # that blew up, or `raise_source_unusable` to model the shard itself being
  # unbuildable, which is a different fact and leaves the worker by a different
  # exit.
  class MockDocsBuilder < DocsBuilder
    record Call, repository_url : String, version : String, commit_sha : String?, work_dir : String

    property calls : Array(Call) = [] of Call
    property docs_json : String = %({"repository_name":"mock","program":{"full_name":"mock","name":"mock"}})
    property should_fail : Bool = false
    property raise_with : String? = nil
    property raise_source_unusable : String? = nil

    def generate_docs(repository_url : String, version : String, commit_sha : String?, work_dir : String) : String?
      @calls << Call.new(repository_url, version, commit_sha, work_dir)

      if message = raise_source_unusable
        raise DocsBuilder::SourceUnusable.new(message)
      end

      if message = raise_with
        raise message
      end

      return nil if should_fail

      docs_dir = File.join(work_dir, "docs")
      Dir.mkdir_p(docs_dir)
      docs_json_path = File.join(docs_dir, "docs.json")
      File.write(docs_json_path, docs_json)
      docs_json_path
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

  # Captures the follow-up jobs IndexShardWorker schedules instead of running
  # them, so an indexing example asserts on what was chained rather than on
  # the whole pipeline downstream of it.
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
