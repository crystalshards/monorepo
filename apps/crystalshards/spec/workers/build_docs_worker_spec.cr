require "../spec_helper"

describe BuildDocsWorker do
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

    # Note: The following tests verify error handling when git clone fails
    # Full integration tests would require mocking git, crystal docs, and MinIO
    # For now, we test the worker's control flow and error resilience

    it "raises error when git clone fails" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/invalid-repo-url-that-does-not-exist-xyz123")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "test-shard",
        version: "1.0.0"
      )

      # This will attempt to clone a non-existent repo and should raise
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

  # Additional unit tests for private methods would require comprehensive mocking:
  # - clone_repository: Mock git commands
  # - checkout_version: Mock git checkout
  # - install_dependencies: Mock shards install
  # - build_docs: Mock crystal docs
  # - upload_to_storage: Mock MinIO uploads
  #
  # These integration-style tests verify the worker's error handling
  # and basic flow control without external dependencies.
end
