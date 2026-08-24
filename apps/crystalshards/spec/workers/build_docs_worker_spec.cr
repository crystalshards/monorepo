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

    # Three builds of one version, and only the first does any work.
    #
    # The registry assertion is what this example was originally written for
    # and it still holds. The upload count is what changed: it used to assert
    # three identical uploads, which described what the fake recorded rather
    # than a contract worth keeping. Nothing in this pipeline can overwrite a
    # published object, so the second and third uploads were a 403 recorded as
    # a build failure and a request Cloud Tasks brought straight back.
    it "publishes once and skips the rebuild for a version it already has" do
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

      builder.calls.size.should eq(1)
      ShardQuery.new.name("idempotent-docs").select_count.should eq(1)
      storage.uploaded_docs.should eq(["idempotent-docs/1.0.0/docs.json"])
    end
  end

  # The loop this split exists to close. crystaldocs re-queues a version whose
  # page a reader opens, the discovery sweep re-queues what it re-reads, and
  # warming re-queues from the popularity ranking, so a version that is already
  # documented is asked for again and again. Each of those used to clone,
  # install dependencies, compile, and only then fail on an upload nothing in
  # this pipeline is permitted to perform.
  describe "a version whose artifact is already published" do
    it "records success and builds nothing at all" do
      shard = ShardFactory.create &.name("already-built")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")
      DocsRows.register("already-built", "1.0.0")
      DocsRows.request("already-built", "1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new
      storage.existing << "already-built/1.0.0/docs.json"

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "already-built", version: "1.0.0").perform
      end

      builder.calls.should be_empty
      storage.uploaded_docs.should be_empty

      # Recorded, not merely skipped. A reader watching the pending page has to
      # be released, and crystaldocs needs a finished build rather than a
      # version nothing ever resolved.
      DocsRows.request_status("already-built", "1.0.0").should eq("succeeded")
      DocsRows.version_status("already-built", "1.0.0").should eq("success")
    end

    # The check runs ahead of ShardQuery, so the artifact answers for the
    # version even when the registry has nothing to say. What a reader is
    # served is the object in the bucket, and the row should report what the
    # bucket holds.
    it "answers from the artifact without needing a registry entry" do
      DocsRows.register("unregistered", "2.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new
      storage.existing << "unregistered/2.0.0/docs.json"

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "unregistered", version: "2.0.0").perform
      end

      builder.calls.should be_empty
      DocsRows.version_status("unregistered", "2.0.0").should eq("success")
    end

    # `force` is the deliberate override, and while the artifact is there it
    # refuses instead of proceeding. Publishing over an existing object needs
    # storage.objects.delete, which nothing in this pipeline holds, so a forced
    # run that cloned and compiled first would spend the entire build to arrive
    # at a 403.
    it "refuses a forced rebuild before spending a build, and records nothing" do
      shard = ShardFactory.create &.name("forced-docs")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")
      DocsRows.register("forced-docs", "1.0.0", build_status: "success")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new
      storage.existing << "forced-docs/1.0.0/docs.json"

      WorkerSeams.with_docs_pipeline(builder, storage) do
        expect_raises(BuildDocsWorker::ForcedRebuildBlocked, /storage\.objects\.delete/) do
          BuildDocsWorker.new(shard_name: "forced-docs", version: "1.0.0", force: true).perform
        end
      end

      builder.calls.should be_empty
      storage.uploaded_docs.should be_empty

      # A documented version is not marked failed to report that somebody's
      # rebuild was blocked. That would be a lie a reader pays for, and it is
      # what starts crystaldocs' retry floor.
      DocsRows.version_status("forced-docs", "1.0.0").should eq("success")
    end

    # Forced with nothing to overwrite is an ordinary build. There is no 403
    # waiting, so there is nothing to refuse.
    it "builds normally when forced and no artifact is in the way" do
      shard = ShardFactory.create &.name("forced-fresh")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "forced-fresh", version: "1.0.0", force: true).perform
      end

      builder.calls.size.should eq(1)
      storage.uploaded_docs.should eq(["forced-fresh/1.0.0/docs.json"])
    end

    # A store that could not answer is not an empty bucket. Reading it as "not
    # there" rebuilds and lands back on the 403; reading it as "there" marks a
    # version documented on no evidence. So the job fails and comes back, which
    # is the one thing that can repair it.
    it "raises when the store cannot say whether the artifact exists" do
      shard = ShardFactory.create &.name("stat-unavailable")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new
      storage.stat_unavailable = true

      WorkerSeams.with_docs_pipeline(builder, storage) do
        expect_raises(CrystalStorage::Unavailable) do
          BuildDocsWorker.new(shard_name: "stat-unavailable", version: "1.0.0").perform
        end
      end

      builder.calls.should be_empty
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

  # Cloud Tasks retries a job that raises, and a retry only earns its clone,
  # its dependency install and its sandboxed compile if the next attempt could
  # come out differently. A shard whose own source or dependency graph is the
  # problem is exactly the case where it cannot: the same published bytes fail
  # the same way every time. Measured on the live queue before this split,
  # 35,918 attempts went against 5,379 tasks created in a week.
  describe "a failure the shard's own source caused" do
    it "records the failure and finishes the task rather than raising" do
      shard = ShardFactory.create &.name("unresolvable-deps")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")
      DocsRows.register("unresolvable-deps", "1.0.0")
      DocsRows.request("unresolvable-deps", "1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      builder.raise_source_unusable =
        "Could not install dependencies, so there is no complete tree to document: " \
        "can't find file 'logger'"
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "unresolvable-deps", version: "1.0.0").perform
      end

      storage.uploaded_docs.should be_empty

      # Recorded, so the reader is told why and the retry floor has a failed_at
      # to measure from. Not raised, so the request is finished instead of being
      # redelivered to fail identically.
      outcome = DocsRows.request_outcome("unresolvable-deps", "1.0.0")
      outcome.status.should eq("failed")
      outcome.failed_at.should_not be_nil
      outcome.last_error.to_s.should contain("can't find file 'logger'")
      DocsRows.version_status("unresolvable-deps", "1.0.0").should eq("failed")
    end

    # The other half of the same decision, and the half a blanket "acknowledge
    # everything" would have destroyed: a failure of ours keeps its redelivery,
    # because the redelivery is what repairs it.
    it "still raises for a failure that is not the shard's fault" do
      shard = ShardFactory.create &.name("infra-failure")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      builder.raise_with = "Could not start the docs build job: 503 unavailable"
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        expect_raises(Exception, /Could not start the docs build job/) do
          BuildDocsWorker.new(shard_name: "infra-failure", version: "1.0.0").perform
        end
      end

      storage.uploaded_docs.should be_empty
    end

    # A permanent failure whose outcome could not be written down is not a
    # finished request: the reader is left on a pending page and nothing else
    # re-derives the result. So this is the one permanent failure that still
    # has to come back.
    it "raises when a permanent failure's own outcome cannot be recorded" do
      shard = ShardFactory.create &.name("unrecordable-permanent")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")
      DocsRows.register("unrecordable-permanent", "1.0.0")

      builder = CrystalShards::MockDocsBuilder.new
      builder.raise_source_unusable =
        "Could not check out 9.9.9, refusing to document a different revision as 1.0.0"
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        DocsRows.refusing_doc_version_writes do
          expect_raises(CrystalShards::DocsBuildStatus::Unrecorded) do
            BuildDocsWorker.new(shard_name: "unrecordable-permanent", version: "1.0.0").perform
          end
        end
      end

      DocsRows.version_status("unrecordable-permanent", "1.0.0").should eq("pending")
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
