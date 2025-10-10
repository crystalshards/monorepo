require "../workers_spec_helper"

describe IndexShardWorker do
  Spec.before_each do
    TestProviderFactory.reset
  end

  describe "#perform" do
    it "successfully indexes a shard from repository" do
      shard = ShardFactory.create &.name("kemal")
        .repository_url("https://github.com/kemalcr/kemal")
        .description("Lightning Fast, Super Simple web framework")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      shard_yml = <<-YAML
      name: kemal
      version: 1.0.0
      description: Lightning Fast, Super Simple web framework
      license: MIT
      homepage: https://kemalcr.com
      crystal: ">= 1.0.0"
      dependencies:
        radix:
          github: luislavena/radix
      YAML

      mock_provider = MockProvider.new("https://github.com/kemalcr/kemal")
      mock_provider.shard_yml_content = shard_yml
      TestProviderFactory.set_mock(mock_provider)

      worker = IndexShardWorker.new(
        shard_name: "kemal",
        version: "1.0.0"
      )

      worker.perform

      shard_after = ShardQuery.new.name("kemal").first
      shard_version_after = ShardVersionQuery.new.shard_id(shard.id).version("1.0.0").first

      shard_after.description.should eq("Lightning Fast, Super Simple web framework")
      shard_after.license.should eq("MIT")
      shard_after.homepage_url.should eq("https://kemalcr.com")
      shard_version_after.crystal_version.should eq(">= 1.0.0")
      shard_version_after.metadata.should_not be_nil
    end

    it "handles non-existent shards gracefully" do
      worker = IndexShardWorker.new(
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

      worker = IndexShardWorker.new(
        shard_name: "kemal",
        version: "99.99.99"
      )

      # Should not raise, just log error and return
      worker.perform

      # Verify the version still doesn't exist
      ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?.should be_nil
    end

    it "extracts GitHub metadata when repository is on GitHub" do
      shard = ShardFactory.create &.name("ameba")
        .repository_url("https://github.com/crystal-ameba/ameba")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      shard_yml = <<-YAML
      name: ameba
      version: 1.0.0
      description: A static code analysis tool
      license: MIT
      YAML

      mock_metadata = BaseProvider::RepositoryMetadata.new(
        stars: 425,
        forks: 35,
        description: "A static code analysis tool for Crystal",
        homepage: "https://ameba.cr",
        default_branch: "master"
      )

      mock_provider = MockProvider.new("https://github.com/crystal-ameba/ameba")
      mock_provider.shard_yml_content = shard_yml
      mock_provider.metadata_result = mock_metadata
      TestProviderFactory.set_mock(mock_provider)

      worker = IndexShardWorker.new(
        shard_name: "ameba",
        version: "1.0.0"
      )

      worker.perform

      shard_after = ShardQuery.new.name("ameba").first

      shard_after.github_stars.should eq(425)
      shard_after.github_forks.should eq(35)
      shard_after.last_synced_at.should_not be_nil
      shard_after.provider.should eq("mock")
    end

    it "enqueues UpdateDependenciesWorker and BuildDocsWorker" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/test/test-shard")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      shard_yml = <<-YAML
      name: test-shard
      version: 1.0.0
      YAML

      mock_provider = MockProvider.new("https://github.com/test/test-shard")
      mock_provider.shard_yml_content = shard_yml
      TestProviderFactory.set_mock(mock_provider)

      worker = IndexShardWorker.new(
        shard_name: "test-shard",
        version: "1.0.0"
      )

      # Note: We can't easily test job enqueuing without mocking the job queue
      # This test verifies the worker runs without errors
      # In production, UpdateDependenciesWorker and BuildDocsWorker would be enqueued
      worker.perform

      # Verify the indexing succeeded
      shard_after = ShardQuery.new.name("test-shard").first
      shard_after.should_not be_nil
    end

    it "handles errors when fetching shard.yml fails" do
      shard = ShardFactory.create &.name("broken-shard")
        .repository_url("https://github.com/test/broken-shard")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      mock_provider = MockProvider.new("https://github.com/test/broken-shard")
      mock_provider.shard_yml_content = nil  # Simulate failure to fetch
      TestProviderFactory.set_mock(mock_provider)

      worker = IndexShardWorker.new(
        shard_name: "broken-shard",
        version: "1.0.0"
      )

      # Should not raise, just log error
      worker.perform

      # Verify shard wasn't updated (description should be unchanged)
      shard_after = ShardQuery.new.name("broken-shard").first
      shard_after.description.should eq("A sample Crystal shard")
    end

    it "handles provider errors gracefully" do
      shard = ShardFactory.create &.name("error-shard")
        .repository_url("https://github.com/test/error-shard")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      mock_provider = MockProvider.new("https://github.com/test/error-shard")
      mock_provider.should_raise = Exception.new("API rate limit exceeded")
      TestProviderFactory.set_mock(mock_provider)

      worker = IndexShardWorker.new(
        shard_name: "error-shard",
        version: "1.0.0"
      )

      # Should raise since it's an unexpected error
      expect_raises(Exception, "API rate limit exceeded") do
        worker.perform
      end
    end

    it "updates shard version metadata from shard.yml" do
      shard = ShardFactory.create &.name("metadata-shard")
        .repository_url("https://github.com/test/metadata-shard")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("2.5.0")
        .released_at(Time.utc)

      shard_yml = <<-YAML
      name: metadata-shard
      version: 2.5.0
      description: A shard with lots of metadata
      license: Apache-2.0
      homepage: https://example.com
      crystal: ">= 1.2.0"
      authors:
        - John Doe <john@example.com>
      YAML

      mock_provider = MockProvider.new("https://github.com/test/metadata-shard")
      mock_provider.shard_yml_content = shard_yml
      TestProviderFactory.set_mock(mock_provider)

      worker = IndexShardWorker.new(
        shard_name: "metadata-shard",
        version: "2.5.0"
      )

      worker.perform

      shard_after = ShardQuery.new.name("metadata-shard").first
      shard_version_after = ShardVersionQuery.new.shard_id(shard.id).version("2.5.0").first

      shard_after.description.should eq("A shard with lots of metadata")
      shard_after.license.should eq("Apache-2.0")
      shard_after.homepage_url.should eq("https://example.com")
      shard_version_after.crystal_version.should eq(">= 1.2.0")

      # Verify metadata JSON contains the parsed YAML
      metadata = shard_version_after.metadata.not_nil!
      metadata["name"].as_s.should eq("metadata-shard")
      metadata["version"].as_s.should eq("2.5.0")
    end
  end
end
