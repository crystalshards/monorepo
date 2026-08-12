require "../spec_helper"

describe BuildDocsWorker do
  describe "successful build" do
    # The artifact lands under the key the build was asked for, because that is
    # the key crystaldocs reads back from. Storing under the shard's name
    # instead left the reader looking somewhere the artifact was not, and gave
    # two same-named shards one key between them.
    it "stores the artifact under the key the build was requested with" do
      shard = ShardFactory.create &.name("doc-test")
        .repository_url("https://github.com/user/doc-test")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.2.3")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "doc-test", version: "1.2.3").perform
      end

      storage.uploaded_docs.should eq(["doc-test/1.2.3/docs.json"])
    end

    # `documentation_url` is the link a maintainer declared. A build used to
    # overwrite it, which destroyed what they declared and turned the has_docs
    # filter into "we generated API docs". Every shard now has a documentation
    # URL by virtue of having an identity, so nothing needs the write.
    it "leaves the maintainer's declared documentation url alone" do
      shard = ShardFactory.create &.name("declared-docs")
        .documentation_url("https://doc-test.example.org/guide")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.2.3")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "declared-docs", version: "1.2.3").perform
      end

      ShardQuery.new.name("declared-docs").first.documentation_url
        .should eq("https://doc-test.example.org/guide")
    end

    it "writes no documentation url for a shard that declared none" do
      shard = ShardFactory.create &.name("undeclared-docs").documentation_url(nil)
      ShardVersionFactory.create &.shard_id(shard.id).version("1.2.3")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "undeclared-docs", version: "1.2.3").perform
      end

      ShardQuery.new.name("undeclared-docs").first.documentation_url.should be_nil
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
      storage.uploaded_docs.should eq([
        "idempotent-docs/1.0.0/docs.json",
        "idempotent-docs/1.0.0/docs.json",
        "idempotent-docs/1.0.0/docs.json",
      ])
    end
  end

  describe "failed build" do
    it "publishes nothing when no docs are produced" do
      shard = ShardFactory.create &.name("build-fail")
        .documentation_url("https://build-fail.example.org/guide")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      builder.should_fail = true
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "build-fail", version: "1.0.0").perform
      end

      storage.uploaded_docs.should be_empty
      ShardQuery.new.name("build-fail").first.documentation_url
        .should eq("https://build-fail.example.org/guide")
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

      storage.uploaded_docs.should be_empty
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

      storage.uploaded_docs.should be_empty
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
      storage.uploaded_docs.should be_empty
      ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?.should be_nil
    end
  end

  # A lost outcome is not a failed build, and this method is where the two used
  # to be confused: every exception left the body through one rescue, which then
  # recorded a failure. So a build that had compiled and uploaded its artifact
  # was recorded as failed the moment the write of its success went wrong.
  describe "when the outcome cannot be recorded" do
    it "does not record a failure for a build that succeeded" do
      shard = ShardFactory.create &.name("unrecordable")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")
      DocsRows.register("unrecordable", "1.0.0")
      DocsRows.request("unrecordable", "1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        DocsRows.refusing_doc_version_writes do
          expect_raises(CrystalShards::DocsBuildStatus::Unrecorded) do
            BuildDocsWorker.new(shard_name: "unrecordable", version: "1.0.0").perform
          end
        end
      end

      # The documentation was built and published. Recording that as a failure
      # would be a lie about it, and 'failed' is also what starts crystaldocs'
      # one hour retry floor, so the lie would then block the rebuild that is
      # the only thing able to record the truth.
      storage.uploaded_docs.should eq(["unrecordable/1.0.0/docs.json"])
      DocsRows.request_status("unrecordable", "1.0.0").should eq("pending")
      DocsRows.version_status("unrecordable", "1.0.0").should eq("pending")
    end

    # Raising is what fails the job, and failing the job is what makes Cloud
    # Tasks redeliver. The redelivery is the entire repair mechanism for a lost
    # outcome, so absorbing this would strand the version silently.
    it "still raises when the build itself failed as well" do
      shard = ShardFactory.create &.name("unrecordable-failure")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")
      DocsRows.register("unrecordable-failure", "1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      builder.raise_with = "Failed to clone repository: fatal: repository not found"
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        DocsRows.refusing_doc_version_writes do
          # The build's own exception, not the recording failure: it is why this
          # path was taken, and either one fails the job.
          expect_raises(Exception, /Failed to clone repository/) do
            BuildDocsWorker.new(shard_name: "unrecordable-failure", version: "1.0.0").perform
          end
        end
      end

      DocsRows.version_status("unrecordable-failure", "1.0.0").should eq("pending")
    end
  end
end
