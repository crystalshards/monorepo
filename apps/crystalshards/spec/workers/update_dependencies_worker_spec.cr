require "../spec_helper"

describe UpdateDependenciesWorker do
  describe "successful dependency parsing" do
    it "parses and stores dependencies from shard.yml metadata" do
      shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      metadata = JSON.parse(%(
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

      db_dep = dependencies.name("db").first
      db_dep.version_requirement.should eq("~> 0.10.0")
      db_dep.scope.should eq("runtime")

      ameba_dep = dependencies.name("ameba").first
      ameba_dep.version_requirement.should eq("~> 1.0.0")
      ameba_dep.scope.should eq("development")
    end

    it "handles dependencies with different version specification formats" do
      shard = ShardFactory.create &.name("complex-deps")
        .repository_url("https://github.com/user/complex-deps")

      metadata = JSON.parse(%(
        {
          "name": "complex-deps",
          "dependencies": {
            "simple": "~> 1.0",
            "github": {"github": "user/repo", "version": ">= 2.0"},
            "gitlab": {"gitlab": "user/repo"},
            "git": {"git": "https://example.com/repo.git", "branch": "main"}
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "complex-deps",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(4)

      simple_dep = dependencies.name("simple").first
      simple_dep.version_requirement.should eq("~> 1.0")

      github_dep = dependencies.name("github").first
      github_dep.version_requirement.should eq(">= 2.0")

      gitlab_dep = dependencies.name("gitlab").first
      gitlab_dep.version_requirement.should eq("*")

      git_dep = dependencies.name("git").first
      git_dep.version_requirement.should eq("*")
    end

    it "links dependencies to dependent shards when they exist" do
      kemal = ShardFactory.create &.name("kemal")
        .repository_url("https://github.com/kemalcr/kemal")

      db = ShardFactory.create &.name("db")
        .repository_url("https://github.com/crystal-lang/crystal-db")

      test_shard = ShardFactory.create &.name("test-shard")
        .repository_url("https://github.com/user/test-shard")

      metadata = JSON.parse(%(
        {
          "name": "test-shard",
          "dependencies": {
            "kemal": "~> 1.0.0",
            "db": "~> 0.10.0",
            "nonexistent": "~> 1.0"
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

      kemal_dependency = DependencyQuery.new
        .shard_version_id(shard_version.id)
        .name("kemal")
        .first

      kemal_dependency.dependent_shard_id.should eq(kemal.id)

      db_dependency = DependencyQuery.new
        .shard_version_id(shard_version.id)
        .name("db")
        .first

      db_dependency.dependent_shard_id.should eq(db.id)

      nonexistent_dependency = DependencyQuery.new
        .shard_version_id(shard_version.id)
        .name("nonexistent")
        .first

      nonexistent_dependency.dependent_shard_id.should be_nil
    end
  end

  describe "error handling" do
    it "handles non-existent shards gracefully" do
      worker = UpdateDependenciesWorker.new(
        shard_name: "nonexistent",
        version: "1.0.0"
      )

      worker.perform

      ShardQuery.new.name("nonexistent").first?.should be_nil
    end

    it "handles non-existent shard versions gracefully" do
      shard = ShardFactory.create &.name("version-test")
        .repository_url("https://github.com/user/version-test")

      worker = UpdateDependenciesWorker.new(
        shard_name: "version-test",
        version: "99.99.99"
      )

      worker.perform

      ShardVersionQuery.new
        .shard_id(shard.id)
        .version("99.99.99")
        .first?.should be_nil
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

    it "handles shard versions with no metadata" do
      shard = ShardFactory.create &.name("no-metadata")
        .repository_url("https://github.com/user/no-metadata")

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)

      worker = UpdateDependenciesWorker.new(
        shard_name: "no-metadata",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(0)
    end

    it "handles shards with only development dependencies" do
      shard = ShardFactory.create &.name("dev-only")
        .repository_url("https://github.com/user/dev-only")

      metadata = JSON.parse(%(
        {
          "name": "dev-only",
          "development_dependencies": {
            "spec": "~> 0.1.0",
            "ameba": "~> 1.0.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "dev-only",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      runtime_deps = dependencies.scope("runtime")
      dev_deps = dependencies.scope("development")

      runtime_deps.select_count.should eq(0)
      dev_deps.select_count.should eq(2)
    end
  end

  describe "idempotency" do
    it "can be run multiple times safely" do
      shard = ShardFactory.create &.name("idempotent-deps")
        .repository_url("https://github.com/user/idempotent-deps")

      metadata = JSON.parse(%(
        {
          "name": "idempotent-deps",
          "dependencies": {
            "kemal": "~> 1.0.0",
            "db": "~> 0.10.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "idempotent-deps",
        version: "1.0.0"
      )

      worker.perform
      worker.perform
      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(2)

      kemal_deps = dependencies.name("kemal")
      kemal_deps.select_count.should eq(1)

      db_deps = dependencies.name("db")
      db_deps.select_count.should eq(1)
    end

    it "replaces old dependencies when re-run" do
      shard = ShardFactory.create &.name("replace-deps")
        .repository_url("https://github.com/user/replace-deps")

      old_metadata = JSON.parse(%(
        {
          "name": "replace-deps",
          "dependencies": {
            "old-dep": "~> 1.0.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(old_metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "replace-deps",
        version: "1.0.0"
      )

      worker.perform

      initial_deps = DependencyQuery.new.shard_version_id(shard_version.id)
      initial_deps.select_count.should eq(1)
      initial_deps.name("old-dep").first?.should_not be_nil

      new_metadata = JSON.parse(%(
        {
          "name": "replace-deps",
          "dependencies": {
            "new-dep": "~> 2.0.0"
          }
        }
      ))

      SaveShardVersion.update(shard_version) do |operation|
        operation.metadata.value = new_metadata
      end

      worker.perform

      updated_deps = DependencyQuery.new.shard_version_id(shard_version.id)
      updated_deps.select_count.should eq(1)
      updated_deps.name("old-dep").first?.should be_nil
      updated_deps.name("new-dep").first?.should_not be_nil
    end
  end

  describe "edge cases" do
    it "handles empty dependencies object" do
      shard = ShardFactory.create &.name("empty-deps")
        .repository_url("https://github.com/user/empty-deps")

      metadata = JSON.parse(%(
        {
          "name": "empty-deps",
          "dependencies": {}
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "empty-deps",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(0)
    end

    it "handles dependencies with special characters in names" do
      shard = ShardFactory.create &.name("special-deps")
        .repository_url("https://github.com/user/special-deps")

      metadata = JSON.parse(%(
        {
          "name": "special-deps",
          "dependencies": {
            "my-shard": "~> 1.0",
            "another_shard": "~> 2.0",
            "shard123": "~> 3.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "special-deps",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(3)

      dependencies.name("my-shard").first?.should_not be_nil
      dependencies.name("another_shard").first?.should_not be_nil
      dependencies.name("shard123").first?.should_not be_nil
    end

    it "handles large number of dependencies" do
      shard = ShardFactory.create &.name("many-deps")
        .repository_url("https://github.com/user/many-deps")

      deps_hash = {} of String => String
      25.times do |i|
        deps_hash["dep-#{i}"] = "~> #{i}.0.0"
      end

      metadata = JSON.parse({
        "name" => "many-deps",
        "dependencies" => deps_hash
      }.to_json)

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "many-deps",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(25)
    end

    it "correctly separates runtime and development dependencies" do
      shard = ShardFactory.create &.name("mixed-deps")
        .repository_url("https://github.com/user/mixed-deps")

      metadata = JSON.parse(%(
        {
          "name": "mixed-deps",
          "dependencies": {
            "runtime1": "~> 1.0",
            "runtime2": "~> 2.0"
          },
          "development_dependencies": {
            "dev1": "~> 1.0",
            "dev2": "~> 2.0",
            "dev3": "~> 3.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "mixed-deps",
        version: "1.0.0"
      )

      worker.perform

      all_deps = DependencyQuery.new.shard_version_id(shard_version.id)
      all_deps.select_count.should eq(5)

      runtime_deps = all_deps.scope("runtime")
      runtime_deps.select_count.should eq(2)

      dev_deps = all_deps.scope("development")
      dev_deps.select_count.should eq(3)
    end

    it "handles version requirements without constraint operators" do
      shard = ShardFactory.create &.name("version-formats")
        .repository_url("https://github.com/user/version-formats")

      metadata = JSON.parse(%(
        {
          "name": "version-formats",
          "dependencies": {
            "exact": "1.0.0",
            "optimistic": "~> 1.0",
            "greater": ">= 1.0.0",
            "range": ">= 1.0.0, < 2.0.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(shard.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "version-formats",
        version: "1.0.0"
      )

      worker.perform

      dependencies = DependencyQuery.new.shard_version_id(shard_version.id)
      dependencies.select_count.should eq(4)

      exact_dep = dependencies.name("exact").first
      exact_dep.version_requirement.should eq("1.0.0")

      optimistic_dep = dependencies.name("optimistic").first
      optimistic_dep.version_requirement.should eq("~> 1.0")

      greater_dep = dependencies.name("greater").first
      greater_dep.version_requirement.should eq(">= 1.0.0")

      range_dep = dependencies.name("range").first
      range_dep.version_requirement.should eq(">= 1.0.0, < 2.0.0")
    end
  end

  describe "dependency graph construction" do
    it "builds correct dependency relationships" do
      base = ShardFactory.create &.name("base")
        .repository_url("https://github.com/user/base")

      dep1 = ShardFactory.create &.name("dep1")
        .repository_url("https://github.com/user/dep1")

      dep2 = ShardFactory.create &.name("dep2")
        .repository_url("https://github.com/user/dep2")

      metadata = JSON.parse(%(
        {
          "name": "base",
          "dependencies": {
            "dep1": "~> 1.0",
            "dep2": "~> 2.0"
          }
        }
      ))

      shard_version = ShardVersionFactory.create &.shard_id(base.id)
        .version("1.0.0")
        .released_at(Time.utc)
        .metadata(metadata)

      worker = UpdateDependenciesWorker.new(
        shard_name: "base",
        version: "1.0.0"
      )

      worker.perform

      dep1_link = DependencyQuery.new
        .shard_version_id(shard_version.id)
        .name("dep1")
        .first

      dep1_link.dependent_shard_id.should eq(dep1.id)

      dep2_link = DependencyQuery.new
        .shard_version_id(shard_version.id)
        .name("dep2")
        .first

      dep2_link.dependent_shard_id.should eq(dep2.id)
    end
  end
end
