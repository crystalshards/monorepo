require "../spec_helper"

describe IndexShardWorker do
  describe "#perform" do
    it "successfully indexes a shard from repository" do
      shard = ShardFactory.create &.name("kemal")
        .repository_url("https://github.com/kemalcr/kemal")
        .description("Initial description")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      fixture_content = File.read("spec/fixtures/valid_shard.yml")
      mock_provider = MockProvider.new(
        repository_url: "https://github.com/kemalcr/kemal",
        shard_yml_content: fixture_content
      )

      worker = IndexShardWorker.new(
        shard_name: "kemal",
        version: "1.0.0",
        provider: mock_provider
      )

      worker.perform

      shard_after = ShardQuery.new.name("kemal").first

      shard_after.description.should eq("Lightning Fast, Super Simple web framework for Crystal")
      shard_after.license.should eq("MIT")
      shard_after.homepage_url.should eq("https://kemalcr.com")

      shard_version_after = ShardVersionQuery.new.shard_id(shard.id).version("1.0.0").first
      shard_version_after.crystal_version.should eq(">= 1.0.0")
      shard_version_after.metadata.should_not be_nil
    end

    it "handles non-existent shards gracefully" do
      worker = IndexShardWorker.new(
        shard_name: "nonexistent",
        version: "1.0.0"
      )

      worker.perform

      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "handles non-existent shard versions gracefully" do
      shard = ShardFactory.create &.name("test-shard")

      worker = IndexShardWorker.new(
        shard_name: "test-shard",
        version: "99.99.99"
      )

      worker.perform

      shard_version = ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?
      shard_version.should be_nil
    end

    it "extracts GitHub metadata when provider supports API" do
      shard = ShardFactory.create &.name("ameba")
        .repository_url("https://github.com/crystal-ameba/ameba")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      fixture_content = File.read("spec/fixtures/valid_shard.yml")
      metadata = BaseProvider::RepositoryMetadata.new(
        stars: 350,
        forks: 45,
        description: "A static code analysis tool for Crystal",
        default_branch: "master"
      )

      mock_provider = MockProvider.new(
        repository_url: "https://github.com/crystal-ameba/ameba",
        shard_yml_content: fixture_content,
        metadata: metadata
      )

      worker = IndexShardWorker.new(
        shard_name: "ameba",
        version: "1.0.0",
        provider: mock_provider
      )

      worker.perform

      shard_after = ShardQuery.new.name("ameba").first

      shard_after.github_stars.should eq(350)
      shard_after.github_forks.should eq(45)
      shard_after.last_synced_at.should_not be_nil
      shard_after.provider.should eq("mock")
      shard_after.repository_type.should eq("git")

      mock_provider.fetch_metadata_calls.should eq(1)
    end

    it "handles missing shard.yml gracefully" do
      shard = ShardFactory.create &.name("broken-shard")
        .repository_url("https://github.com/user/broken")
        .description(nil)

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      mock_provider = MockProvider.new(
        repository_url: "https://github.com/user/broken",
        shard_yml_content: nil
      )

      worker = IndexShardWorker.new(
        shard_name: "broken-shard",
        version: "1.0.0",
        provider: mock_provider
      )

      worker.perform

      shard_after = ShardQuery.new.name("broken-shard").first
      shard_after.description.should be_nil
    end

    it "handles provider fetch errors gracefully" do
      shard = ShardFactory.create &.name("error-shard")
        .repository_url("https://github.com/user/error")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      fixture_content = File.read("spec/fixtures/valid_shard.yml")
      mock_provider = MockProvider.new(
        repository_url: "https://github.com/user/error",
        shard_yml_content: fixture_content
      )
      mock_provider.simulate_fetch_error = true

      worker = IndexShardWorker.new(
        shard_name: "error-shard",
        version: "1.0.0",
        provider: mock_provider
      )

      worker.perform

      mock_provider.fetch_shard_yml_calls.should eq(["1.0.0"])
    end

    it "updates metadata from minimal shard.yml" do
      shard = ShardFactory.create &.name("simple-shard")
        .repository_url("https://github.com/user/simple")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      fixture_content = File.read("spec/fixtures/minimal_shard.yml")
      mock_provider = MockProvider.new(
        repository_url: "https://github.com/user/simple",
        shard_yml_content: fixture_content
      )

      worker = IndexShardWorker.new(
        shard_name: "simple-shard",
        version: "1.0.0",
        provider: mock_provider
      )

      worker.perform

      shard_after = ShardQuery.new.name("simple-shard").first
      shard_after.description.should be_nil
      shard_after.license.should be_nil

      shard_version_after = ShardVersionQuery.new.shard_id(shard.id).version("1.0.0").first
      shard_version_after.metadata.should_not be_nil
    end

    it "handles metadata fetch errors gracefully" do
      shard = ShardFactory.create &.name("metadata-error")
        .repository_url("https://github.com/user/metadata-error")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      fixture_content = File.read("spec/fixtures/valid_shard.yml")
      metadata = BaseProvider::RepositoryMetadata.new(stars: 100)
      mock_provider = MockProvider.new(
        repository_url: "https://github.com/user/metadata-error",
        shard_yml_content: fixture_content,
        metadata: metadata
      )
      mock_provider.simulate_metadata_error = true

      worker = IndexShardWorker.new(
        shard_name: "metadata-error",
        version: "1.0.0",
        provider: mock_provider
      )

      worker.perform

      shard_after = ShardQuery.new.name("metadata-error").first
      shard_after.github_stars.should be_nil
    end

    it "stores shard.yml metadata as JSON in shard_version" do
      shard = ShardFactory.create &.name("json-test")
        .repository_url("https://github.com/user/json-test")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      fixture_content = File.read("spec/fixtures/shard_with_deps.yml")
      mock_provider = MockProvider.new(
        repository_url: "https://github.com/user/json-test",
        shard_yml_content: fixture_content
      )

      worker = IndexShardWorker.new(
        shard_name: "json-test",
        version: "1.0.0",
        provider: mock_provider
      )

      worker.perform

      shard_version_after = ShardVersionQuery.new.shard_id(shard.id).version("1.0.0").first
      metadata = shard_version_after.metadata.not_nil!

      metadata["name"].as_s.should eq("test-shard")
      metadata["dependencies"]?.should_not be_nil
      metadata["dependencies"]["kemal"]?.should_not be_nil
    end
  end
end
