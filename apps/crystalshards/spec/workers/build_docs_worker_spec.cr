require "../spec_helper"

# Mock the StorageService for BuildDocsWorker tests
class BuildDocsWorker
  # Override upload_to_storage to use mock storage in tests
  @@mock_storage_service : CrystalShards::MockStorageService?

  def self.set_mock_storage(service : CrystalShards::MockStorageService)
    @@mock_storage_service = service
  end

  def self.reset_mock_storage
    @@mock_storage_service = nil
  end

  private def upload_to_storage(shard : Shard, shard_version : ShardVersion, docs_dir : String) : String
    if mock = @@mock_storage_service
      # Use mock storage
      mock.upload_docs(shard.name, shard_version.version, docs_dir)
      "https://crystaldocs.org/#{shard.name}/#{shard_version.version}"
    else
      # Original implementation
      storage = CrystalShards::StorageService.new
      uploaded_keys = storage.upload_docs(shard.name, shard_version.version, docs_dir)
      log_info "Uploaded #{uploaded_keys.size} documentation files to MinIO"
      "https://crystaldocs.org/#{shard.name}/#{shard_version.version}"
    end
  rescue ex : Exception
    log_error "Error uploading docs to MinIO", ex
    raise ex
  end
end

describe BuildDocsWorker do
  Spec.before_each do
    BuildDocsWorker.reset_mock_storage
  end

  describe "#perform" do
    it "handles non-existent shards gracefully" do
      worker = BuildDocsWorker.new(
        shard_name: "nonexistent",
        version: "1.0.0"
      )

      # Should not raise, just log error and return
      worker.perform

      # Verify no crash occurred
      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "handles non-existent shard versions gracefully" do
      shard = ShardFactory.create &.name("kemal")
        .repository_url("https://github.com/kemalcr/kemal")

      worker = BuildDocsWorker.new(
        shard_name: "kemal",
        version: "99.99.99"
      )

      # Should not raise, just log error and return
      worker.perform

      # Verify the version still doesn't exist
      ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?.should be_nil
    end

    # Note: The following tests are integration-style tests that would require
    # actual git repositories and crystal docs generation. In a real test environment,
    # we would mock these external dependencies. For now, we're testing the worker
    # logic paths that we can control.

    it "logs error when documentation build fails" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/invalid-repo-url-that-does-not-exist-xyz123")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      mock_storage = CrystalShards::MockStorageService.new
      BuildDocsWorker.set_mock_storage(mock_storage)

      worker = BuildDocsWorker.new(
        shard_name: "test-shard",
        version: "1.0.0"
      )

      # This will attempt to clone a non-existent repo and should fail gracefully
      expect_raises(Exception) do
        worker.perform
      end

      # Verify documentation_url was not set
      shard_after = ShardQuery.new.name("test-shard").first
      shard_after.documentation_url.should be_nil
    end

    it "does not update documentation_url when build fails" do
      shard = ShardFactory.create &.name("fail-shard")
        .repository_url("https://github.com/user/nonexistent-repo-xyz123")
        .documentation_url(nil)

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "fail-shard",
        version: "1.0.0"
      )

      # Should raise due to clone failure
      expect_raises(Exception) do
        worker.perform
      end

      # Verify documentation_url remains nil
      shard_after = ShardQuery.new.name("fail-shard").first
      shard_after.documentation_url.should be_nil
    end
  end

  # Additional unit tests for private methods would go here
  # In production, we would create more comprehensive mocks for:
  # - clone_repository
  # - checkout_version
  # - install_dependencies
  # - build_docs
  # - upload_to_storage
  #
  # For now, these integration-style tests verify the worker's error handling
  # and basic flow control. Full coverage would require mocking git, crystal docs,
  # and file system operations.
end
