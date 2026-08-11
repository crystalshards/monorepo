require "../spec_helper"

describe BuildDocsWorker do
  describe "successful build" do
    it "publishes a documentation url for the shard and version" do
      shard = ShardFactory.create &.name("doc-test")
        .repository_url("https://github.com/user/doc-test")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.2.3")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "doc-test", version: "1.2.3").perform
      end

      ShardQuery.new.name("doc-test").first.documentation_url
        .should eq("https://crystaldocs.org/doc-test/1.2.3")
    end

    it "builds from the shard's repository at the recorded commit" do
      shard = ShardFactory.create &.name("commit-sha")
        .repository_url("https://github.com/user/commit-sha")
      ShardVersionFactory.create &.shard_id(shard.id)
        .version("0.1.0")
        .commit_sha("deadbeef123456")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "commit-sha", version: "0.1.0").perform
      end

      builder.calls.size.should eq(1)
      call = builder.calls.first
      call.repository_url.should eq("https://github.com/user/commit-sha")
      call.version.should eq("0.1.0")
      call.commit_sha.should eq("deadbeef123456")
    end

    it "passes a nil commit sha through when the version has none" do
      shard = ShardFactory.create &.name("no-sha")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "no-sha", version: "1.0.0").perform
      end

      builder.calls.first.commit_sha.should be_nil
    end

    it "uploads the generated docs.json under the shard and version prefix" do
      shard = ShardFactory.create &.name("upload-test")
      ShardVersionFactory.create &.shard_id(shard.id).version("2.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "upload-test", version: "2.0.0").perform
      end

      # Exactly one artifact ever lands in storage for a version, and it is
      # the JSON document, never a tree of shard-authored HTML.
      storage.uploaded_docs.should eq(["upload-test/2.0.0/docs.json"])
    end

    it "removes the working directory once the build finishes" do
      shard = ShardFactory.create &.name("cleanup-test")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "cleanup-test", version: "1.0.0").perform
      end

      work_dir = builder.calls.first.work_dir
      Dir.exists?(work_dir).should be_false
    end

    it "republishes on a rebuild without duplicating the shard" do
      shard = ShardFactory.create &.name("idempotent-docs")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        worker = BuildDocsWorker.new(shard_name: "idempotent-docs", version: "1.0.0")
        worker.perform
        worker.perform
        worker.perform
      end

      builder.calls.size.should eq(3)
      ShardQuery.new.name("idempotent-docs").select_count.should eq(1)
      ShardQuery.new.name("idempotent-docs").first.documentation_url
        .should eq("https://crystaldocs.org/idempotent-docs/1.0.0")
    end
  end

  describe "failed build" do
    it "leaves the previous documentation url in place when no docs are produced" do
      shard = ShardFactory.create &.name("build-fail")
        .documentation_url("https://crystaldocs.org/build-fail/0.9.0")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      builder.should_fail = true
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "build-fail", version: "1.0.0").perform
      end

      ShardQuery.new.name("build-fail").first.documentation_url
        .should eq("https://crystaldocs.org/build-fail/0.9.0")
      storage.uploaded_docs.should be_empty
    end

    it "re-raises a clone failure and publishes nothing" do
      shard = ShardFactory.create &.name("clone-fail")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      builder.raise_with = "Failed to clone repository: fatal: repository not found"
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        expect_raises(Exception, /Failed to clone repository/) do
          BuildDocsWorker.new(shard_name: "clone-fail", version: "1.0.0").perform
        end
      end

      ShardQuery.new.name("clone-fail").first.documentation_url.should be_nil
    end

    it "re-raises an upload failure, publishes nothing and still cleans up" do
      shard = ShardFactory.create &.name("upload-fail")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new
      storage.should_fail = true

      WorkerSeams.with_docs_pipeline(builder, storage) do
        expect_raises(Exception, /Storage upload failed/) do
          BuildDocsWorker.new(shard_name: "upload-fail", version: "1.0.0").perform
        end
      end

      ShardQuery.new.name("upload-fail").first.documentation_url.should be_nil
      Dir.exists?(builder.calls.first.work_dir).should be_false
    end
  end

  describe "missing records" do
    it "returns without raising or building when the shard is unknown" do
      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "nonexistent", version: "1.0.0").perform
      end

      builder.calls.should be_empty
      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "returns without raising or building when the version is unknown" do
      shard = ShardFactory.create &.name("no-version")
      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "no-version", version: "99.99.99").perform
      end

      builder.calls.should be_empty
      ShardQuery.new.name("no-version").first.documentation_url.should be_nil
      ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?.should be_nil
    end
  end
end
