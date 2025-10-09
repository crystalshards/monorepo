require "../spec_helper"

describe UpdateDependenciesWorker do
  describe "#perform" do
    it "parses and stores dependencies from shard.yml metadata" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      metadata = JSON.parse(%(
        {
          "name": "test-shard",
          "dependencies": {
            "kemal": "~> 1.0.0",
            "db": {"github": "crystal-lang/crystal-db"}
          },
          "development_dependencies": {
            "ameba": "~> 1.0.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "test-shard",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      runtime_deps = dependencies.scope("runtime")
      dev_deps = dependencies.scope("development")

      runtime_deps.select_count.should eq(2)
      dev_deps.select_count.should eq(1)

      kemal_dep = dependencies.name("kemal").first
      kemal_dep.version_requirement.should eq("~> 1.0.0")
      kemal_dep.scope.should eq("runtime")

      ameba_dep = dependencies.name("ameba").first
      ameba_dep.scope.should eq("development")
    end

    it "handles shards with no dependencies" do
      shard = ShardFactory.create &.name("simple-shard")
        .repository_url("https://github.com/user/simple-shard")

      metadata = JSON.parse(%({"name": "simple-shard"}))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "simple-shard",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(0)
    end

    it "links dependencies to dependent shards when they exist" do
      kemal = ShardFactory.create &.name("kemal")
        .repository_url("https://github.com/kemalcr/kemal")

      test_shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      metadata = JSON.parse(%(
        {
          "name": "test-shard",
          "dependencies": {
            "kemal": "~> 1.0.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(test_shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "test-shard",
        version: "1.0.0"
      )

      worker.perform

      dependency = DependencyQuery.new
        .shard_version_id(shard_version.id)
        .name("kemal")
        .first

      dependency.dependent_shard_id.should eq(kemal.id)
    end

    it "handles non-existent shards gracefully" do
      worker = UpdateDependenciesWorker.new(
        shard_name: "nonexistent",
        version: "1.0.0"
      )

      worker.perform

      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "handles non-existent shard versions gracefully" do
      shard = ShardFactory.create &.name("test-shard")

      worker = UpdateDependenciesWorker.new(
        shard_name: "test-shard",
        version: "99.99.99"
      )

      worker.perform

      shard_version = ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?
      shard_version.should be_nil
    end

    it "handles missing metadata gracefully" do
      shard = ShardFactory.create &.name("no-metadata")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(nil)

      worker = UpdateDependenciesWorker.new(
        shard_name: "no-metadata",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(0)
    end

    it "extracts version requirement from string format" do
      shard = ShardFactory.create &.name("string-deps")

      metadata = JSON.parse(%(
        {
          "name": "string-deps",
          "dependencies": {
            "simple": "~> 1.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "string-deps",
        version: "1.0.0"
      )

      worker.perform

      dependency = DependencyQuery.new.shard_version_id(shard_version.id).name("simple").first
      dependency.version_requirement.should eq("~> 1.0")
    end

    it "extracts version requirement from hash format with version" do
      shard = ShardFactory.create &.name("hash-deps")

      metadata = JSON.parse(%(
        {
          "name": "hash-deps",
          "dependencies": {
            "complex": {
              "github": "user/repo",
              "version": ">= 2.0.0"
            }
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "hash-deps",
        version: "1.0.0"
      )

      worker.perform

      dependency = DependencyQuery.new.shard_version_id(shard_version.id).name("complex").first
      dependency.version_requirement.should eq(">= 2.0.0")
    end

    it "uses wildcard for hash format without version" do
      shard = ShardFactory.create &.name("wildcard-deps")

      metadata = JSON.parse(%(
        {
          "name": "wildcard-deps",
          "dependencies": {
            "unversioned": {
              "github": "user/repo"
            }
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "wildcard-deps",
        version: "1.0.0"
      )

      worker.perform

      dependency = DependencyQuery.new.shard_version_id(shard_version.id).name("unversioned").first
      dependency.version_requirement.should eq("*")
    end

    it "replaces existing dependencies when run multiple times (idempotent)" do
      shard = ShardFactory.create &.name("idempotent-test")

      metadata = JSON.parse(%(
        {
          "name": "idempotent-test",
          "dependencies": {
            "dep1": "~> 1.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "idempotent-test",
        version: "1.0.0"
      )

      worker.perform
      first_count = DependencyQuery.new.shard_version_id(shard_version.id).select_count

      worker.perform
      second_count = DependencyQuery.new.shard_version_id(shard_version.id).select_count

      first_count.should eq(1)
      second_count.should eq(1)
    end

    it "handles dependencies that are not yet in the registry" do
      shard = ShardFactory.create &.name("new-shard")

      metadata = JSON.parse(%(
        {
          "name": "new-shard",
          "dependencies": {
            "unknown-shard": "~> 1.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "new-shard",
        version: "1.0.0"
      )

      worker.perform

      dependency = DependencyQuery.new.shard_version_id(shard_version.id).name("unknown-shard").first
      dependency.name.should eq("unknown-shard")
      dependency.dependent_shard_id.should be_nil
    end
  end
end
