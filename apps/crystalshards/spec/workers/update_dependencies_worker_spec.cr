require "../spec_helper"

describe UpdateDependenciesWorker do
  it "parses and stores dependencies from shard.yml metadata" do
    shard = ShardBox.create &.name("test-shard")
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

    shard_version = ShardVersionBox.create &.shard_id(shard.id)
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
    shard = ShardBox.create &.name("simple-shard")
      .repository_url("https://github.com/user/simple-shard")

    metadata = JSON.parse(%({"name": "simple-shard"}))

    shard_version = ShardVersionBox.create &.shard_id(shard.id)
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
    kemal = ShardBox.create &.name("kemal")
      .repository_url("https://github.com/kemalcr/kemal")

    test_shard = ShardBox.create &.name("test-shard")
      .repository_url("https://github.com/user/test-shard")

    metadata = JSON.parse(%(
      {
        "name": "test-shard",
        "dependencies": {
          "kemal": "~> 1.0.0"
        }
      }
    ))

    shard_version = ShardVersionBox.create &.shard_id(test_shard.id)
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
end
