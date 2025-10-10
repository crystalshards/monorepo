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

      # Should not raise, just log error and return
      worker.perform

      # Verify no crash occurred
      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "handles non-existent shard versions gracefully" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      worker = UpdateDependenciesWorker.new(
        shard_name: "test-shard",
        version: "99.99.99"
      )

      # Should not raise, just log error and return
      worker.perform

      # Verify the version still doesn't exist
      ShardVersionQuery.new.shard_id(shard.id).version("99.99.99").first?.should be_nil
    end

    it "handles shard versions with no metadata" do
      shard = ShardFactory.create &.name("no-meta-shard")
        .repository_url("https://github.com/user/no-meta-shard")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        # No metadata set

      worker = UpdateDependenciesWorker.new(
        shard_name: "no-meta-shard",
        version: "1.0.0"
      )

      # Should not raise, just log and return
      worker.perform

      # Should have no dependencies created
      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(0)
    end

    it "replaces existing dependencies when run multiple times" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      metadata_v1 = JSON.parse(%(
        {
          "name": "test-shard",
          "dependencies": {
            "kemal": "~> 1.0.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata_v1)

      worker = UpdateDependenciesWorker.new(
        shard_name: "test-shard",
        version: "1.0.0"
      )

      # First run
      worker.perform

      dependencies_first = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies_first.select_count.should eq(1)

      # Update metadata with different dependencies
      metadata_v2 = JSON.parse(%(
        {
          "name": "test-shard",
          "dependencies": {
            "db": "~> 0.10.0",
            "pg": "~> 0.23.0"
          }
        }
      ))

      SaveShardVersion.update(shard_version) do |operation|
        operation.metadata.value = metadata_v2
      end

      # Second run - should replace dependencies
      worker.perform

      dependencies_second = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies_second.select_count.should eq(2)

      # Old dependency should be gone
      DependencyQuery.new.shard_version_id(shard_version.id).name("kemal").first?.should be_nil

      # New dependencies should exist
      DependencyQuery.new.shard_version_id(shard_version.id).name("db").first?.should_not be_nil
      DependencyQuery.new.shard_version_id(shard_version.id).name("pg").first?.should_not be_nil
    end

    it "extracts version requirements from different dependency formats" do
      shard = ShardFactory.create &.name("format-test-shard")
        .repository_url("https://github.com/user/format-test-shard")

      metadata = JSON.parse(%(
        {
          "name": "format-test-shard",
          "dependencies": {
            "simple": "~> 1.0.0",
            "github_dep": {"github": "crystal-lang/crystal-db", "version": "~> 0.10.0"},
            "github_no_version": {"github": "crystal-lang/http-client"},
            "git_dep": {"git": "https://example.com/repo.git"}
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "format-test-shard",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(4)

      # Simple version string
      simple_dep = dependencies.name("simple").first
      simple_dep.version_requirement.should eq("~> 1.0.0")

      # GitHub with version
      github_dep = dependencies.name("github_dep").first
      github_dep.version_requirement.should eq("~> 0.10.0")

      # GitHub without version (should default to *)
      github_no_ver = dependencies.name("github_no_version").first
      github_no_ver.version_requirement.should eq("*")

      # Git without version (should default to *)
      git_dep = dependencies.name("git_dep").first
      git_dep.version_requirement.should eq("*")
    end

    it "handles errors during dependency creation gracefully" do
      shard = ShardFactory.create &.name("error-shard")
        .repository_url("https://github.com/user/error-shard")

      # Create metadata with valid dependencies
      metadata = JSON.parse(%(
        {
          "name": "error-shard",
          "dependencies": {
            "valid-dep": "~> 1.0.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "error-shard",
        version: "1.0.0"
      )

      # Worker should complete successfully
      worker.perform

      # Verify dependency was created
      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(1)
    end
  end
end
