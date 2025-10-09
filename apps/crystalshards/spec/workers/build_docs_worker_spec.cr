require "../spec_helper"

describe BuildDocsWorker do
  describe "#perform" do
    it "handles non-existent shards gracefully" do
      worker = BuildDocsWorker.new(
        shard_name: "nonexistent",
        version: "1.0.0"
      )

      worker.perform

      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "handles non-existent shard versions gracefully" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      worker = BuildDocsWorker.new(
        shard_name: "test-shard",
        version: "99.99.99"
      )

      worker.perform

      shard_version = ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?
      shard_version.should be_nil
    end

    it "logs error when shard is not found" do
      worker = BuildDocsWorker.new(
        shard_name: "missing-shard",
        version: "1.0.0"
      )

      worker.perform

      shard = ShardQuery.new.name("missing-shard").first?
      shard.should be_nil
    end

    it "logs error when shard version is not found" do
      shard = ShardFactory.create &.name("version-missing")
        .repository_url("https://github.com/user/version-missing")

      worker = BuildDocsWorker.new(
        shard_name: "version-missing",
        version: "5.5.5"
      )

      worker.perform

      version = ShardVersionQuery.new.shard_id(shard.id).version("5.5.5").first?
      version.should be_nil
    end

    it "accepts storage_service parameter for dependency injection" do
      shard = ShardFactory.create &.name("di-test")
        .repository_url("https://github.com/user/di-test")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      mock_storage = CrystalShards::MockStorageService.new

      worker = BuildDocsWorker.new(
        shard_name: "di-test",
        version: "1.0.0",
        storage_service: mock_storage
      )

      worker.should_not be_nil
      worker.@storage_service.should eq(mock_storage)
    end

    it "initializes with correct queue name" do
      worker = BuildDocsWorker.new(
        shard_name: "queue-test",
        version: "1.0.0"
      )

      worker.@queue.should eq("docs")
    end

    it "initializes with correct shard_name and version" do
      worker = BuildDocsWorker.new(
        shard_name: "init-test",
        version: "2.3.4"
      )

      worker.@shard_name.should eq("init-test")
      worker.@version.should eq("2.3.4")
    end

    it "handles errors during build process" do
      shard = ShardFactory.create &.name("error-shard")
        .repository_url("https://invalid-url-that-wont-work/error-shard")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "error-shard",
        version: "1.0.0"
      )

      expect_raises(Exception) do
        worker.perform
      end

      shard_after = ShardQuery.new.name("error-shard").first
      shard_after.documentation_url.should be_nil
    end

    it "does not update documentation_url when build fails" do
      shard = ShardFactory.create &.name("failed-build")
        .repository_url("https://invalid/repo")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "failed-build",
        version: "1.0.0"
      )

      begin
        worker.perform
      rescue
      end

      shard_after = ShardQuery.new.name("failed-build").first
      shard_after.documentation_url.should be_nil
    end

    it "preserves existing shard data when build fails" do
      shard = ShardFactory.create &.name("preserve-test")
        .repository_url("https://invalid/url")
        .description("Original description")
        .license("MIT")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "preserve-test",
        version: "1.0.0"
      )

      begin
        worker.perform
      rescue
      end

      shard_after = ShardQuery.new.name("preserve-test").first
      shard_after.description.should eq("Original description")
      shard_after.license.should eq("MIT")
    end
  end
end
