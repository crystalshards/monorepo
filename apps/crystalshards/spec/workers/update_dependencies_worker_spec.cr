require "../spec_helper"

private def version_with_metadata(shard : Shard, metadata : String) : ShardVersion
  ShardVersionFactory.create &.shard_id(shard.id)
    .version("1.0.0")
    .metadata(JSON.parse(metadata))
end

describe UpdateDependenciesWorker do
  describe "storing dependencies" do
    it "creates a row per runtime and development dependency" do
      shard = ShardFactory.create &.name("test-shard")
      version = version_with_metadata(shard, <<-JSON)
        {
          "name": "test-shard",
          "dependencies": {
            "kemal": "~> 1.0.0",
            "db": "~> 0.10.0"
          },
          "development_dependencies": {
            "ameba": "~> 1.0.0"
          }
        }
        JSON

      UpdateDependenciesWorker.new(shard_name: "test-shard", version: "1.0.0").perform

      DependencyQuery.new.shard_version_id(version.id).scope("runtime").select_count.should eq(2)
      DependencyQuery.new.shard_version_id(version.id).scope("development").select_count.should eq(1)

      kemal = DependencyQuery.new.shard_version_id(version.id).name("kemal").first
      kemal.version_requirement.should eq("~> 1.0.0")
      kemal.scope.should eq("runtime")

      ameba = DependencyQuery.new.shard_version_id(version.id).name("ameba").first
      ameba.version_requirement.should eq("~> 1.0.0")
      ameba.scope.should eq("development")
    end

    it "reads the version requirement off both string and object specs" do
      shard = ShardFactory.create &.name("complex-deps")
      version = version_with_metadata(shard, <<-JSON)
        {
          "name": "complex-deps",
          "dependencies": {
            "simple": "~> 1.0",
            "pinned": {"github": "user/repo", "version": ">= 2.0"},
            "unpinned": {"gitlab": "user/repo"}
          }
        }
        JSON

      UpdateDependenciesWorker.new(shard_name: "complex-deps", version: "1.0.0").perform

      deps = DependencyQuery.new.shard_version_id(version.id)
      deps.select_count.should eq(3)
      deps.name("simple").first.version_requirement.should eq("~> 1.0")
      deps.name("pinned").first.version_requirement.should eq(">= 2.0")
      # An object spec without a "version" key has no requirement to record.
      deps.name("unpinned").first.version_requirement.should eq("*")
    end

    it "links a dependency to the shard it names, when that shard is indexed" do
      kemal = ShardFactory.create &.name("kemal")
      consumer = ShardFactory.create &.name("consumer")
      version = version_with_metadata(consumer, <<-JSON)
        {
          "name": "consumer",
          "dependencies": {
            "kemal": "~> 1.0.0",
            "not-indexed": "~> 1.0"
          }
        }
        JSON

      UpdateDependenciesWorker.new(shard_name: "consumer", version: "1.0.0").perform

      deps = DependencyQuery.new.shard_version_id(version.id)
      deps.name("kemal").first.dependent_shard_id.should eq(kemal.id)
      deps.name("not-indexed").first.dependent_shard_id.should be_nil
    end
  end

  describe "re-running against changed metadata" do
    it "replaces the previous dependency set" do
      shard = ShardFactory.create &.name("replace-deps")
      version = version_with_metadata(shard, <<-JSON)
        {"name": "replace-deps", "dependencies": {"old-dep": "~> 1.0.0"}}
        JSON

      worker = UpdateDependenciesWorker.new(shard_name: "replace-deps", version: "1.0.0")
      worker.perform

      DependencyQuery.new.shard_version_id(version.id).name("old-dep").first?.should_not be_nil

      operation = SaveShardVersion.new(version)
      operation.metadata.value = JSON.parse(%({"name": "replace-deps", "dependencies": {"new-dep": "~> 2.0.0"}}))
      operation.update!

      worker.perform

      deps = DependencyQuery.new.shard_version_id(version.id)
      deps.select_count.should eq(1)
      deps.name("old-dep").first?.should be_nil
      deps.name("new-dep").first.version_requirement.should eq("~> 2.0.0")
    end

    it "does not accumulate duplicates across repeated runs" do
      shard = ShardFactory.create &.name("idempotent-deps")
      version = version_with_metadata(shard, <<-JSON)
        {
          "name": "idempotent-deps",
          "dependencies": {"kemal": "~> 1.0.0", "db": "~> 0.10.0"}
        }
        JSON

      worker = UpdateDependenciesWorker.new(shard_name: "idempotent-deps", version: "1.0.0")
      worker.perform
      worker.perform
      worker.perform

      DependencyQuery.new.shard_version_id(version.id).select_count.should eq(2)
      DependencyQuery.new.shard_version_id(version.id).name("kemal").select_count.should eq(1)
    end
  end

  describe "nothing to store" do
    it "stores nothing when the version has no metadata" do
      shard = ShardFactory.create &.name("no-metadata")
      version = ShardVersionFactory.create &.shard_id(shard.id).version("1.0.0")

      UpdateDependenciesWorker.new(shard_name: "no-metadata", version: "1.0.0").perform

      DependencyQuery.new.shard_version_id(version.id).select_count.should eq(0)
    end

    it "stores nothing when the metadata declares no dependencies key" do
      shard = ShardFactory.create &.name("simple-shard")
      version = version_with_metadata(shard, %({"name": "simple-shard"}))

      UpdateDependenciesWorker.new(shard_name: "simple-shard", version: "1.0.0").perform

      DependencyQuery.new.shard_version_id(version.id).select_count.should eq(0)
    end

    it "skips development dependencies when the runtime dependencies key is absent" do
      # parse_and_store_dependencies returns early without a "dependencies"
      # key, so development dependencies alone are never reached.
      shard = ShardFactory.create &.name("dev-only")
      version = version_with_metadata(shard, <<-JSON)
        {
          "name": "dev-only",
          "development_dependencies": {"ameba": "~> 1.0.0"}
        }
        JSON

      UpdateDependenciesWorker.new(shard_name: "dev-only", version: "1.0.0").perform

      DependencyQuery.new.shard_version_id(version.id).select_count.should eq(0)
    end

    it "clears existing rows when the metadata declares an empty dependency set" do
      shard = ShardFactory.create &.name("empty-deps")
      version = version_with_metadata(shard, %({"name": "empty-deps", "dependencies": {"gone": "~> 1.0"}}))

      worker = UpdateDependenciesWorker.new(shard_name: "empty-deps", version: "1.0.0")
      worker.perform
      DependencyQuery.new.shard_version_id(version.id).select_count.should eq(1)

      operation = SaveShardVersion.new(version)
      operation.metadata.value = JSON.parse(%({"name": "empty-deps", "dependencies": {}}))
      operation.update!

      worker.perform

      DependencyQuery.new.shard_version_id(version.id).select_count.should eq(0)
    end
  end

  describe "missing records" do
    it "returns without raising when the shard is unknown" do
      UpdateDependenciesWorker.new(shard_name: "nonexistent", version: "1.0.0").perform

      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "returns without raising when the version is unknown" do
      shard = ShardFactory.create &.name("version-test")

      UpdateDependenciesWorker.new(shard_name: "version-test", version: "99.99.99").perform

      ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?.should be_nil
    end
  end
end
