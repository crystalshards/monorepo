require "../spec_helper"

# Queue payloads carry the canonical slug, so a job for one of two same-named
# shards cannot land on the other. The wire field is still called shard_name,
# because that is the format crystaldocs produces and this proves both spellings
# resolve correctly.
describe "workers keyed on identity" do
  describe IndexShardWorker do
    it "indexes the shard the slug names, not its namesake" do
      github, gitlab = create_same_name_pair_with_versions

      provider = MockProvider.new("https://gitlab.com/acme/router")
      provider.shard_yml_content = YAML.parse(<<-YAML)
        name: router
        description: Indexed from GitLab
        license: MIT
        YAML

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do
          IndexShardWorker.new(shard_name: "gitlab.com/acme/router", version: "1.0.0").perform
        end
      end

      ShardQuery.new.id(gitlab.id).first.description.should eq("Indexed from GitLab")
      ShardQuery.new.id(github.id).first.description.should eq("The GitHub router")
    end

    it "chains follow-up jobs on the identity, never the bare name" do
      _, gitlab = create_same_name_pair_with_versions

      provider = MockProvider.new(gitlab.repository_url)
      provider.shard_yml_content = YAML.parse("name: router\n")

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do |followups|
          IndexShardWorker.new(shard_name: "gitlab.com/acme/router", version: "1.0.0").perform

          followups.should eq([
            {IndexShardWorker::Followup::UpdateDependencies, "gitlab.com/acme/router", "1.0.0"},
          ])
        end
      end
    end

    # A job enqueued under a bare name before this change, or by crystaldocs,
    # still runs, and the chain it kicks off is upgraded to the identity.
    it "accepts a legacy bare name and chains the identity it resolved" do
      shard = ShardFactory.create &.name("solo")
        .repository_url("https://github.com/someone/solo")
      ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      provider = MockProvider.new(shard.repository_url)
      provider.shard_yml_content = YAML.parse("name: solo\n")

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do |followups|
          IndexShardWorker.new(shard_name: "solo", version: "1.0.0").perform

          followups.map(&.[1]).uniq.should eq(["github.com/someone/solo"])
        end
      end
    end

    it "indexes neither when a bare name is ambiguous" do
      github, gitlab = create_same_name_pair_with_versions

      provider = MockProvider.new("https://github.com/kemalcr/router")
      provider.shard_yml_content = YAML.parse("name: router\ndescription: Should not land\n")

      WorkerSeams.with_provider(provider) do
        WorkerSeams.capturing_followups do |followups|
          IndexShardWorker.new(shard_name: "router", version: "1.0.0").perform

          followups.should be_empty
        end
      end

      ShardQuery.new.id(github.id).first.description.should eq("The GitHub router")
      ShardQuery.new.id(gitlab.id).first.description.should eq("The GitLab router")
    end
  end

  describe UpdateDependenciesWorker do
    it "records dependencies against the shard the slug names" do
      github, gitlab = create_same_name_pair_with_versions

      gitlab_version = ShardVersionQuery.new.shard_id(gitlab.id).version("1.0.0").first
      SaveShardVersion.update!(
        gitlab_version,
        metadata: JSON.parse(%({"dependencies":{"kemal":{"github":"kemalcr/kemal"}}}))
      )

      UpdateDependenciesWorker.new(shard_name: "gitlab.com/acme/router", version: "1.0.0").perform

      DependencyQuery.new.shard_version_id(gitlab_version.id).select_count.should eq(1)

      github_version = ShardVersionQuery.new.shard_id(github.id).version("1.0.0").first
      DependencyQuery.new.shard_version_id(github_version.id).select_count.should eq(0)
    end

    # A dependency says which host it comes from, so the edge points at one
    # repository rather than at whichever shard shares the name.
    it "resolves a dependency by the host its shard.yml names" do
      github_kemal = ShardFactory.create &.name("kemal")
        .repository_url("https://github.com/kemalcr/kemal")
      gitlab_kemal = ShardFactory.create &.name("kemal")
        .repository_url("https://gitlab.com/impostor/kemal")

      consumer = ShardFactory.create &.name("consumer")
        .repository_url("https://github.com/someone/consumer")
      version = ShardVersionFactory.create &.shard_id(consumer.id)
        .version("1.0.0")
        .metadata(JSON.parse(%({"dependencies":{"kemal":{"gitlab":"impostor/kemal"}}})))

      UpdateDependenciesWorker.new(shard_name: "github.com/someone/consumer", version: "1.0.0").perform

      dependency = DependencyQuery.new.shard_version_id(version.id).name("kemal").first
      dependency.dependent_shard_id.should eq(gitlab_kemal.id)
      dependency.dependent_shard_id.should_not eq(github_kemal.id)
    end

    it "records the requirement without an edge when the dependency is ambiguous" do
      ShardFactory.create &.name("kemal").repository_url("https://github.com/kemalcr/kemal")
      ShardFactory.create &.name("kemal").repository_url("https://gitlab.com/impostor/kemal")

      consumer = ShardFactory.create &.name("consumer")
        .repository_url("https://github.com/someone/consumer")
      version = ShardVersionFactory.create &.shard_id(consumer.id)
        .version("1.0.0")
        .metadata(JSON.parse(%({"dependencies":{"kemal":"~> 1.0"}})))

      UpdateDependenciesWorker.new(shard_name: "github.com/someone/consumer", version: "1.0.0").perform

      dependency = DependencyQuery.new.shard_version_id(version.id).name("kemal").first
      dependency.version_requirement.should eq("~> 1.0")
      dependency.dependent_shard_id.should be_nil
    end
  end

  describe BuildDocsWorker do
    it "builds the shard the slug names, and stores it under that slug" do
      _, _ = create_same_name_pair_with_versions

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "gitlab.com/acme/router", version: "1.0.0").perform
      end

      builder.calls.size.should eq(1)
      builder.calls.first.repository_url.should eq("https://gitlab.com/acme/router")

      # Not "router/1.0.0/docs.json". Both shards are called router, so a key
      # made from the name would have each build overwrite the other's
      # documentation, and crystaldocs reads back from the slug it asked with.
      storage.uploaded_docs.should eq(["gitlab.com/acme/router/1.0.0/docs.json"])
    end

    it "builds nothing when a bare name is ambiguous" do
      _, _ = create_same_name_pair_with_versions

      builder = CrystalShards::MockDocsBuilder.new
      storage = CrystalShards::MockStorageService.new

      WorkerSeams.with_docs_pipeline(builder, storage) do
        BuildDocsWorker.new(shard_name: "router", version: "1.0.0").perform
      end

      builder.calls.should be_empty
      storage.uploaded_docs.should be_empty
    end
  end
end
