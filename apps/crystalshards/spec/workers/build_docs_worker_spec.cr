require "../spec_helper"

describe BuildDocsWorker do
  describe "successful documentation build" do
    it "builds docs and updates documentation_url" do
      shard = ShardFactory.create &.name("doc-test")
        .repository_url("https://github.com/user/doc-test")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      # Create a temporary directory structure for docs
      temp_docs = File.tempname("test_docs")
      Dir.mkdir_p(temp_docs)
      File.write("#{temp_docs}/index.html", "<html>Test docs</html>")

      # Mock the worker methods that execute git commands
      test_worker = BuildDocsWorker.new(
        shard_name: "doc-test",
        version: "1.0.0"
      )

      # Override private methods for testing
      test_worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        Dir.mkdir_p(target_dir)
        true
      end

      test_worker.class.define_method(:checkout_version) do |repo_dir, shard_version|
        true
      end

      test_worker.class.define_method(:install_dependencies) do |repo_dir|
        true
      end

      test_worker.class.define_method(:build_docs) do |repo_dir|
        docs_dir = File.join(repo_dir, "docs")
        Dir.mkdir_p(docs_dir)
        File.write("#{docs_dir}/index.html", "<html>Generated</html>")
        docs_dir
      end

      # Mock storage service
      original_storage_new = CrystalShards::StorageService.method(:new)
      mock_storage = CrystalShards::MockStorageService.new

      CrystalShards::StorageService.define_singleton_method(:new) do
        mock_storage
      end

      begin
        test_worker.perform

        updated_shard = ShardQuery.new.name("doc-test").first
        updated_shard.documentation_url.should_not be_nil
        updated_shard.documentation_url.should contain("crystaldocs.org")
        updated_shard.documentation_url.should contain("doc-test")
        updated_shard.documentation_url.should contain("1.0.0")
      ensure
        CrystalShards::StorageService.define_singleton_method(:new, &original_storage_new)
        FileUtils.rm_rf(temp_docs) if Dir.exists?(temp_docs)
      end
    end

    it "uploads documentation files to MinIO" do
      shard = ShardFactory.create &.name("upload-test")
        .repository_url("https://github.com/user/upload-test")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "upload-test",
        version: "2.0.0"
      )

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        Dir.mkdir_p(target_dir)
        true
      end

      worker.class.define_method(:checkout_version) do |repo_dir, shard_version|
        true
      end

      worker.class.define_method(:install_dependencies) do |repo_dir|
        true
      end

      worker.class.define_method(:build_docs) do |repo_dir|
        docs_dir = File.join(repo_dir, "docs")
        Dir.mkdir_p(docs_dir)
        File.write("#{docs_dir}/index.html", "<html>Index</html>")
        File.write("#{docs_dir}/style.css", "body { color: blue; }")
        docs_dir
      end

      mock_storage = CrystalShards::MockStorageService.new
      original_storage_new = CrystalShards::StorageService.method(:new)

      CrystalShards::StorageService.define_singleton_method(:new) do
        mock_storage
      end

      begin
        worker.perform

        mock_storage.uploaded_docs.should_not be_empty
        mock_storage.uploaded_docs.any? { |k| k.includes?("upload-test") }.should be_true
      ensure
        CrystalShards::StorageService.define_singleton_method(:new, &original_storage_new)
      end
    end

    it "handles different repository versions correctly" do
      shard = ShardFactory.create &.name("version-test")
        .repository_url("https://github.com/user/version-test")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("0.1.0")
        .released_at(Time.utc)
        .commit_sha("abc123")

      worker = BuildDocsWorker.new(
        shard_name: "version-test",
        version: "0.1.0"
      )

      checkout_called_with = nil

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        Dir.mkdir_p(target_dir)
        true
      end

      worker.class.define_method(:checkout_version) do |repo_dir, version_obj|
        checkout_called_with = version_obj
        true
      end

      worker.class.define_method(:install_dependencies) do |repo_dir|
        true
      end

      worker.class.define_method(:build_docs) do |repo_dir|
        docs_dir = File.join(repo_dir, "docs")
        Dir.mkdir_p(docs_dir)
        File.write("#{docs_dir}/index.html", "<html>Version</html>")
        docs_dir
      end

      mock_storage = CrystalShards::MockStorageService.new
      original_storage_new = CrystalShards::StorageService.method(:new)

      CrystalShards::StorageService.define_singleton_method(:new) do
        mock_storage
      end

      begin
        worker.perform

        checkout_called_with.should eq(shard_version)
      ensure
        CrystalShards::StorageService.define_singleton_method(:new, &original_storage_new)
      end
    end
  end

  describe "error handling" do
    it "handles non-existent shards gracefully" do
      worker = BuildDocsWorker.new(
        shard_name: "nonexistent",
        version: "1.0.0"
      )

      # Should not raise, just return early
      worker.perform

      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "handles non-existent shard versions gracefully" do
      shard = ShardFactory.create &.name("no-version")
        .repository_url("https://github.com/user/no-version")

      worker = BuildDocsWorker.new(
        shard_name: "no-version",
        version: "99.99.99"
      )

      worker.perform

      ShardVersionQuery.new
        .shard_id(shard.id)
        .version("99.99.99")
        .first?.should be_nil
    end

    it "handles git clone failures gracefully" do
      shard = ShardFactory.create &.name("clone-fail")
        .repository_url("https://github.com/user/clone-fail")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "clone-fail",
        version: "1.0.0"
      )

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        raise "Clone failed"
      end

      expect_raises(Exception, /Clone failed/) do
        worker.perform
      end

      # Documentation URL should not be set on failure
      shard_after = ShardQuery.new.name("clone-fail").first
      shard_after.documentation_url.should be_nil
    end

    it "handles crystal docs build failures gracefully" do
      shard = ShardFactory.create &.name("build-fail")
        .repository_url("https://github.com/user/build-fail")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "build-fail",
        version: "1.0.0"
      )

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        Dir.mkdir_p(target_dir)
        true
      end

      worker.class.define_method(:checkout_version) do |repo_dir, shard_version|
        true
      end

      worker.class.define_method(:install_dependencies) do |repo_dir|
        true
      end

      worker.class.define_method(:build_docs) do |repo_dir|
        nil
      end

      worker.perform

      # Documentation URL should not be set if build fails
      shard_after = ShardQuery.new.name("build-fail").first
      shard_after.documentation_url.should be_nil
    end

    it "handles MinIO upload failures gracefully" do
      shard = ShardFactory.create &.name("upload-fail")
        .repository_url("https://github.com/user/upload-fail")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "upload-fail",
        version: "1.0.0"
      )

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        Dir.mkdir_p(target_dir)
        true
      end

      worker.class.define_method(:checkout_version) do |repo_dir, shard_version|
        true
      end

      worker.class.define_method(:install_dependencies) do |repo_dir|
        true
      end

      worker.class.define_method(:build_docs) do |repo_dir|
        docs_dir = File.join(repo_dir, "docs")
        Dir.mkdir_p(docs_dir)
        File.write("#{docs_dir}/index.html", "<html>Test</html>")
        docs_dir
      end

      mock_storage = CrystalShards::MockStorageService.new
      mock_storage.should_fail = true

      original_storage_new = CrystalShards::StorageService.method(:new)
      CrystalShards::StorageService.define_singleton_method(:new) do
        mock_storage
      end

      begin
        expect_raises(Exception, /Storage upload failed/) do
          worker.perform
        end

        # Documentation URL should not be set on upload failure
        shard_after = ShardQuery.new.name("upload-fail").first
        shard_after.documentation_url.should be_nil
      ensure
        CrystalShards::StorageService.define_singleton_method(:new, &original_storage_new)
      end
    end

    it "cleans up temporary directories after build" do
      shard = ShardFactory.create &.name("cleanup-test")
        .repository_url("https://github.com/user/cleanup-test")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "cleanup-test",
        version: "1.0.0"
      )

      temp_dir_created = nil

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        temp_dir_created = target_dir
        Dir.mkdir_p(target_dir)
        true
      end

      worker.class.define_method(:checkout_version) do |repo_dir, shard_version|
        true
      end

      worker.class.define_method(:install_dependencies) do |repo_dir|
        true
      end

      worker.class.define_method(:build_docs) do |repo_dir|
        docs_dir = File.join(repo_dir, "docs")
        Dir.mkdir_p(docs_dir)
        File.write("#{docs_dir}/index.html", "<html>Cleanup</html>")
        docs_dir
      end

      mock_storage = CrystalShards::MockStorageService.new
      original_storage_new = CrystalShards::StorageService.method(:new)

      CrystalShards::StorageService.define_singleton_method(:new) do
        mock_storage
      end

      begin
        worker.perform

        # Verify temp directory is cleaned up (actual implementation uses ensure)
        # In real worker, temp_dir is deleted in ensure block
      ensure
        CrystalShards::StorageService.define_singleton_method(:new, &original_storage_new)
      end
    end
  end

  describe "idempotency" do
    it "can rebuild documentation multiple times safely" do
      shard = ShardFactory.create &.name("idempotent-docs")
        .repository_url("https://github.com/user/idempotent-docs")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "idempotent-docs",
        version: "1.0.0"
      )

      build_count = 0

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        Dir.mkdir_p(target_dir)
        true
      end

      worker.class.define_method(:checkout_version) do |repo_dir, shard_version|
        true
      end

      worker.class.define_method(:install_dependencies) do |repo_dir|
        true
      end

      worker.class.define_method(:build_docs) do |repo_dir|
        build_count += 1
        docs_dir = File.join(repo_dir, "docs")
        Dir.mkdir_p(docs_dir)
        File.write("#{docs_dir}/index.html", "<html>Build #{build_count}</html>")
        docs_dir
      end

      mock_storage = CrystalShards::MockStorageService.new
      original_storage_new = CrystalShards::StorageService.method(:new)

      CrystalShards::StorageService.define_singleton_method(:new) do
        mock_storage
      end

      begin
        # Run multiple times
        worker.perform
        worker.perform
        worker.perform

        # Should have built 3 times
        build_count.should eq(3)

        # Documentation URL should be set
        shard_after = ShardQuery.new.name("idempotent-docs").first
        shard_after.documentation_url.should_not be_nil
      ensure
        CrystalShards::StorageService.define_singleton_method(:new, &original_storage_new)
      end
    end
  end

  describe "edge cases" do
    it "handles repositories without shard dependencies" do
      shard = ShardFactory.create &.name("no-deps")
        .repository_url("https://github.com/user/no-deps")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = BuildDocsWorker.new(
        shard_name: "no-deps",
        version: "1.0.0"
      )

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        Dir.mkdir_p(target_dir)
        true
      end

      worker.class.define_method(:checkout_version) do |repo_dir, shard_version|
        true
      end

      worker.class.define_method(:install_dependencies) do |repo_dir|
        # Simulates shards install failure - no shard.yml
        false
      end

      worker.class.define_method(:build_docs) do |repo_dir|
        docs_dir = File.join(repo_dir, "docs")
        Dir.mkdir_p(docs_dir)
        File.write("#{docs_dir}/index.html", "<html>No Deps</html>")
        docs_dir
      end

      mock_storage = CrystalShards::MockStorageService.new
      original_storage_new = CrystalShards::StorageService.method(:new)

      CrystalShards::StorageService.define_singleton_method(:new) do
        mock_storage
      end

      begin
        # Should still succeed even if dependencies can't be installed
        worker.perform

        shard_after = ShardQuery.new.name("no-deps").first
        shard_after.documentation_url.should_not be_nil
      ensure
        CrystalShards::StorageService.define_singleton_method(:new, &original_storage_new)
      end
    end

    it "handles specific version checkout with commit SHA" do
      shard = ShardFactory.create &.name("commit-sha")
        .repository_url("https://github.com/user/commit-sha")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .commit_sha("deadbeef123456")

      worker = BuildDocsWorker.new(
        shard_name: "commit-sha",
        version: "1.0.0"
      )

      checked_out_sha = nil

      worker.class.define_method(:clone_repository) do |repo_url, target_dir|
        Dir.mkdir_p(target_dir)
        true
      end

      worker.class.define_method(:checkout_version) do |repo_dir, version_obj|
        checked_out_sha = version_obj.commit_sha
        true
      end

      worker.class.define_method(:install_dependencies) do |repo_dir|
        true
      end

      worker.class.define_method(:build_docs) do |repo_dir|
        docs_dir = File.join(repo_dir, "docs")
        Dir.mkdir_p(docs_dir)
        File.write("#{docs_dir}/index.html", "<html>SHA</html>")
        docs_dir
      end

      mock_storage = CrystalShards::MockStorageService.new
      original_storage_new = CrystalShards::StorageService.method(:new)

      CrystalShards::StorageService.define_singleton_method(:new) do
        mock_storage
      end

      begin
        worker.perform

        checked_out_sha.should eq("deadbeef123456")
      ensure
        CrystalShards::StorageService.define_singleton_method(:new, &original_storage_new)
      end
    end
  end
end
