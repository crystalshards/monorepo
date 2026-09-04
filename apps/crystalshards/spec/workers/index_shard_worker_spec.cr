require "../spec_helper"

describe IndexShardWorker do
  describe "shard.yml metadata" do
    it "copies description, license and homepage onto the shard" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")
        .description("Initial description")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new("https://github.com/user/test-shard")
      provider.shard_yml_content = YAML.parse(<<-YAML)
        name: test-shard
        version: 1.0.0
        description: Updated description from shard.yml
        license: MIT
        homepage: https://example.com
        crystal: ">= 1.0.0"
        YAML

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "test-shard", version: "1.0.0").perform
        end
      end

      updated = ShardQuery.new.name("test-shard").first
      updated.description.should eq("Updated description from shard.yml")
      updated.license.should eq("MIT")
      updated.homepage_url.should eq("https://example.com")
    end

    it "records the crystal requirement and the whole shard.yml as version metadata" do
      shard = ShardFactory.create &.name("meta-shard")
      version = ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse(<<-YAML)
        name: meta-shard
        version: 1.0.0
        crystal: ">= 1.0.0"
        dependencies:
          kemal:
            github: kemalcr/kemal
        YAML

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "meta-shard", version: "1.0.0").perform
        end
      end

      updated = ShardVersionQuery.new.shard_id(shard.id).version("1.0.0").first
      updated.crystal_version.should eq(">= 1.0.0")

      metadata = updated.metadata.should_not be_nil
      metadata["name"].as_s.should eq("meta-shard")
      metadata["dependencies"]["kemal"]["github"].as_s.should eq("kemalcr/kemal")
    end

    it "leaves fields the shard.yml omits untouched" do
      shard = ShardFactory.create &.name("partial-shard")
        .description("Existing description")
        .license("Apache-2.0")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse(<<-YAML)
        name: partial-shard
        homepage: https://partial.example.com
        YAML

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "partial-shard", version: "1.0.0").perform
        end
      end

      updated = ShardQuery.new.name("partial-shard").first
      updated.homepage_url.should eq("https://partial.example.com")
      updated.description.should eq("Existing description")
      updated.license.should eq("Apache-2.0")
    end

    it "leaves the shard alone when the repository has no shard.yml" do
      shard = ShardFactory.create &.name("no-yml").description("Untouched")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = nil

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "no-yml", version: "1.0.0").perform
        end
      end

      updated = ShardQuery.new.name("no-yml").first
      updated.description.should eq("Untouched")
      ShardVersionQuery.new.shard_id(shard.id).version("1.0.0").first.metadata.should be_nil
    end
  end

  describe "readme" do
    it "stores the readme the provider returns" do
      shard = ShardFactory.create &.name("readme-shard")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse("name: readme-shard")
      provider.readme_content = "# readme-shard\n\nUsage instructions."

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "readme-shard", version: "1.0.0").perform
        end
      end

      ShardQuery.new.name("readme-shard").first.readme_content
        .should eq("# readme-shard\n\nUsage instructions.")
    end

    it "leaves readme_content nil when the provider has no readme" do
      shard = ShardFactory.create &.name("no-readme")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse("name: no-readme\ndescription: Indexed anyway")
      provider.readme_content = nil

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "no-readme", version: "1.0.0").perform
        end
      end

      updated = ShardQuery.new.name("no-readme").first
      updated.readme_content.should be_nil
      # The rest of the indexing run still happened.
      updated.description.should eq("Indexed anyway")
    end
  end

  describe "provider metadata" do
    it "records stars, forks and sync time when the provider exposes an api" do
      shard = ShardFactory.create &.name("api-shard")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse("name: api-shard")
      provider.api_support = true
      provider.metadata = BaseProvider::RepositoryMetadata.new(
        stars: 100,
        forks: 50,
        description: "GitHub description",
        homepage: "https://crystal-lang.org",
        default_branch: "main"
      )

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "api-shard", version: "1.0.0").perform
        end
      end

      updated = ShardQuery.new.name("api-shard").first
      updated.github_stars.should eq(100)
      updated.github_forks.should eq(50)
      updated.last_synced_at.should_not be_nil
      # MockProvider inherits BaseProvider#provider_name, which strips the
      # "_provider" suffix off the underscored class name.
      updated.provider.should eq("mock")
    end

    it "does not touch provider metadata when the provider has no api" do
      shard = ShardFactory.create &.name("no-api")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse("name: no-api")
      provider.api_support = false
      provider.metadata = BaseProvider::RepositoryMetadata.new(stars: 100, forks: 50)

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "no-api", version: "1.0.0").perform
        end
      end

      updated = ShardQuery.new.name("no-api").first
      updated.github_stars.should be_nil
      updated.github_forks.should be_nil
      updated.last_synced_at.should be_nil
      updated.provider.should eq("github")
    end
  end

  describe "worker chaining" do
    # Follow-ups are keyed on the shard's identity, not the string the job
    # arrived under, so the rest of the pipeline cannot land on a different
    # shard that happens to share this one's name.
    it "schedules dependency and docs jobs for the indexed version" do
      shard = ShardFactory.create &.name("chain-test")
        .repository_url("https://github.com/someone/chain-test")
      ShardVersionFactory.create &.shard_id(shard.id).version("2.1.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse("name: chain-test")

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do |followups|
          IndexShardWorker.new(shard_name: "github.com/someone/chain-test", version: "2.1.0").perform

          # Documentation is not chained here on purpose. It is built when a
          # reader asks for it, so indexing a shard must not queue a compile
          # for a version nobody has opened.
          followups.should eq([
            {IndexShardWorker::Followup::UpdateDependencies, "github.com/someone/chain-test", "2.1.0"},
          ])
        end
      end
    end

    it "does not schedule follow-up jobs when shard.yml could not be fetched" do
      shard = ShardFactory.create &.name("unfetched")
        .repository_url("https://github.com/someone/unfetched")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = nil

      WorkerSeams.with_provider(provider) do
        dispatched = [] of {IndexShardWorker::Followup, String, String}
        original_dispatcher = IndexShardWorker.dispatcher
        IndexShardWorker.dispatcher = ->(followup : IndexShardWorker::Followup, shard_name : String, version : String) {
          dispatched << {followup, shard_name, version}
          nil
        }

        begin
          IndexShardWorker.new(shard_name: "github.com/someone/unfetched", version: "1.0.0").perform

          dispatched.should be_empty
        ensure
          IndexShardWorker.dispatcher = original_dispatcher
        end
      end
    end
  end

  describe "missing records" do
    it "returns without raising or chaining when the shard is unknown" do
      WorkerSeams.capturing_followups do |followups|
        IndexShardWorker.new(shard_name: "nonexistent", version: "1.0.0").perform

        followups.should be_empty
      end

      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "returns without raising or chaining when the version is unknown" do
      shard = ShardFactory.create &.name("version-test").description("Untouched")

      WorkerSeams.capturing_followups do |followups|
        IndexShardWorker.new(shard_name: "version-test", version: "99.99.99").perform

        followups.should be_empty
      end

      ShardQuery.new.name("version-test").first.description.should eq("Untouched")
      ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?.should be_nil
    end
  end

  describe "repeat runs" do
    it "converges on the latest shard.yml without duplicating rows" do
      shard = ShardFactory.create &.name("idempotent-test").description("Initial")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse("name: idempotent-test\ndescription: Updated description")

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          worker = IndexShardWorker.new(shard_name: "idempotent-test", version: "1.0.0")
          worker.perform
          worker.perform
          worker.perform
        end
      end

      ShardQuery.new.name("idempotent-test").select_count.should eq(1)
      ShardVersionQuery.new.shard_id(shard.id).select_count.should eq(1)
      ShardQuery.new.name("idempotent-test").first.description.should eq("Updated description")
    end
  end
end
