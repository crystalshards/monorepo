require "../spec_helper"

describe IndexShardWorker do
  describe "successful indexing" do
    it "processes shard metadata from shard.yml correctly" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
        .description("Initial description")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      # Setup mock provider with shard.yml content
      shard_yml = YAML.parse(%(
        name: test-shard
        version: 1.0.0
        description: Updated description from shard.yml
        license: MIT
        homepage: https://example.com
        crystal: ">= 1.0.0"
      ))

      mock_provider = MockProvider.new("https://github.com/user/test-shard")
      mock_provider.shard_yml_content = shard_yml
      mock_provider.api_support = false

      # Temporarily replace ProviderFactory
      original_create = ProviderFactory.method(:create)
      ProviderFactory.define_singleton_method(:create) do |url|
        mock_provider
      end

      begin
        worker = IndexShardWorker.new(
          shard_name: "test-shard",
          version: "1.0.0"
        )

        worker.perform

        # Verify shard was updated with shard.yml metadata
        updated_shard = ShardQuery.new.name("test-shard").first
        updated_shard.description.should eq("Updated description from shard.yml")
        updated_shard.license.should eq("MIT")
        updated_shard.homepage_url.should eq("https://example.com")

        # Verify shard version was updated
        updated_version = ShardVersionQuery.new
          .shard_id(shard.id)
          .version("1.0.0")
          .first

        updated_version.crystal_version.should eq(">= 1.0.0")
        updated_version.metadata.should_not be_nil
      ensure
        # Restore original method
        ProviderFactory.define_singleton_method(:create, &original_create)
      end
    end

    it "fetches and updates GitHub metadata when repository is on GitHub" do
      shard = ShardFactory.create &.name("github-shard")
        .repository_url("https://github.com/crystal-lang/crystal")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      # Setup mock provider with metadata
      shard_yml = YAML.parse(%(
        name: github-shard
        version: 1.0.0
      ))

      metadata = BaseProvider::RepositoryMetadata.new(
        stars: 100,
        forks: 50,
        description: "GitHub description",
        homepage: "https://crystal-lang.org",
        default_branch: "main"
      )

      mock_provider = MockProvider.new("https://github.com/crystal-lang/crystal")
      mock_provider.shard_yml_content = shard_yml
      mock_provider.metadata = metadata
      mock_provider.api_support = true

      original_create = ProviderFactory.method(:create)
      ProviderFactory.define_singleton_method(:create) do |url|
        mock_provider
      end

      begin
        worker = IndexShardWorker.new(
          shard_name: "github-shard",
          version: "1.0.0"
        )

        worker.perform

        updated_shard = ShardQuery.new.name("github-shard").first
        updated_shard.github_stars.should eq(100)
        updated_shard.github_forks.should eq(50)
        updated_shard.last_synced_at.should_not be_nil
      ensure
        ProviderFactory.define_singleton_method(:create, &original_create)
      end
    end
  end

  describe "worker chaining" do
    it "enqueues UpdateDependenciesWorker after indexing" do
      shard = ShardFactory.create &.name("chain-test")
        .repository_url("https://github.com/user/chain-test")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      shard_yml = YAML.parse(%(
        name: chain-test
        version: 1.0.0
      ))

      mock_provider = MockProvider.new("https://github.com/user/chain-test")
      mock_provider.shard_yml_content = shard_yml

      original_create = ProviderFactory.method(:create)
      ProviderFactory.define_singleton_method(:create) do |url|
        mock_provider
      end

      # Track enqueued workers
      enqueued_update_deps = false
      original_enqueue = UpdateDependenciesWorker.method(:enqueue)
      UpdateDependenciesWorker.define_singleton_method(:enqueue) do |shard_name, version|
        enqueued_update_deps = true
        nil
      end

      begin
        worker = IndexShardWorker.new(
          shard_name: "chain-test",
          version: "1.0.0"
        )

        worker.perform

        enqueued_update_deps.should be_true
      ensure
        ProviderFactory.define_singleton_method(:create, &original_create)
        UpdateDependenciesWorker.define_singleton_method(:enqueue, &original_enqueue)
      end
    end

    it "enqueues BuildDocsWorker after indexing" do
      shard = ShardFactory.create &.name("build-test")
        .repository_url("https://github.com/user/build-test")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      shard_yml = YAML.parse(%(
        name: build-test
        version: 1.0.0
      ))

      mock_provider = MockProvider.new("https://github.com/user/build-test")
      mock_provider.shard_yml_content = shard_yml

      original_create = ProviderFactory.method(:create)
      ProviderFactory.define_singleton_method(:create) do |url|
        mock_provider
      end

      enqueued_build_docs = false
      original_enqueue = BuildDocsWorker.method(:enqueue)
      BuildDocsWorker.define_singleton_method(:enqueue) do |shard_name, version|
        enqueued_build_docs = true
        nil
      end

      begin
        worker = IndexShardWorker.new(
          shard_name: "build-test",
          version: "1.0.0"
        )

        worker.perform

        enqueued_build_docs.should be_true
      ensure
        ProviderFactory.define_singleton_method(:create, &original_create)
        BuildDocsWorker.define_singleton_method(:enqueue, &original_enqueue)
      end
    end
  end

  describe "error handling" do
    it "handles non-existent shards gracefully" do
      worker = IndexShardWorker.new(
        shard_name: "nonexistent",
        version: "1.0.0"
      )

      # Should not raise, just log error and return
      worker.perform

      # Verify shard was not created
      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "handles non-existent shard versions gracefully" do
      shard = ShardFactory.create &.name("version-test")
        .repository_url("https://github.com/user/version-test")

      worker = IndexShardWorker.new(
        shard_name: "version-test",
        version: "99.99.99"
      )

      # Should not raise, just log error and return
      worker.perform

      # Verify no version was created
      ShardVersionQuery.new
        .shard_id(shard.id)
        .version("99.99.99")
        .first?.should be_nil
    end

    it "handles missing shard.yml gracefully" do
      shard = ShardFactory.create &.name("no-yml")
        .repository_url("https://github.com/user/no-yml")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      mock_provider = MockProvider.new("https://github.com/user/no-yml")
      mock_provider.shard_yml_content = nil

      original_create = ProviderFactory.method(:create)
      ProviderFactory.define_singleton_method(:create) do |url|
        mock_provider
      end

      begin
        worker = IndexShardWorker.new(
          shard_name: "no-yml",
          version: "1.0.0"
        )

        # Should not raise, just log error
        worker.perform

        # Still enqueues downstream workers even if shard.yml is missing
        # This is the current behavior - workers are resilient
      ensure
        ProviderFactory.define_singleton_method(:create, &original_create)
      end
    end

    it "handles provider fetch errors gracefully" do
      shard = ShardFactory.create &.name("error-shard")
        .repository_url("https://github.com/user/error-shard")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      mock_provider = MockProvider.new("https://github.com/user/error-shard")
      mock_provider.should_fail = true

      original_create = ProviderFactory.method(:create)
      ProviderFactory.define_singleton_method(:create) do |url|
        mock_provider
      end

      begin
        worker = IndexShardWorker.new(
          shard_name: "error-shard",
          version: "1.0.0"
        )

        worker.perform

        # Worker completes even if provider fails
      ensure
        ProviderFactory.define_singleton_method(:create, &original_create)
      end
    end
  end

  describe "idempotency" do
    it "can be run multiple times safely" do
      shard = ShardFactory.create &.name("idempotent-test")
        .repository_url("https://github.com/user/idempotent-test")
        .description("Initial")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      shard_yml = YAML.parse(%(
        name: idempotent-test
        version: 1.0.0
        description: Updated description
      ))

      mock_provider = MockProvider.new("https://github.com/user/idempotent-test")
      mock_provider.shard_yml_content = shard_yml

      original_create = ProviderFactory.method(:create)
      ProviderFactory.define_singleton_method(:create) do |url|
        mock_provider
      end

      # Suppress worker enqueuing for this test
      original_update_enqueue = UpdateDependenciesWorker.method(:enqueue)
      original_build_enqueue = BuildDocsWorker.method(:enqueue)
      UpdateDependenciesWorker.define_singleton_method(:enqueue) { |shard_name, version| nil }
      BuildDocsWorker.define_singleton_method(:enqueue) { |shard_name, version| nil }

      begin
        worker = IndexShardWorker.new(
          shard_name: "idempotent-test",
          version: "1.0.0"
        )

        # Run multiple times
        worker.perform
        worker.perform
        worker.perform

        # Should still only have one shard and one version
        ShardQuery.new.name("idempotent-test").select_count.should eq(1)
        ShardVersionQuery.new.shard_id(shard.id).select_count.should eq(1)

        # Description should be updated
        updated_shard = ShardQuery.new.name("idempotent-test").first
        updated_shard.description.should eq("Updated description")
      ensure
        ProviderFactory.define_singleton_method(:create, &original_create)
        UpdateDependenciesWorker.define_singleton_method(:enqueue, &original_update_enqueue)
        BuildDocsWorker.define_singleton_method(:enqueue, &original_build_enqueue)
      end
    end
  end
end
