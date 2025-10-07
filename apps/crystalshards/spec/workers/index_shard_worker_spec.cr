require "../spec_helper"

describe IndexShardWorker do
  it "successfully indexes a shard from repository" do
    shard = ShardBox.create &.name("kemal")
      .repository_url("https://github.com/kemalcr/kemal")
      .description("Lightning Fast, Super Simple web framework")

    shard_version = ShardVersionBox.create &.shard_id(shard.id)
      .version("1.0.0")
      .released_at(Time.utc)

    worker = IndexShardWorker.new(
      shard_name: "kemal",
      version: "1.0.0"
    )

    worker.perform

    shard_after = ShardQuery.new.name("kemal").first

    shard_after.description.should_not be_nil
    shard_after.license.should_not be_nil
  end

  it "handles non-existent shards gracefully" do
    worker = IndexShardWorker.new(
      shard_name: "nonexistent",
      version: "1.0.0"
    )

    expect_raises(Exception) do
      worker.perform
    end
  end

  it "extracts GitHub metadata when repository is on GitHub" do
    shard = ShardBox.create &.name("ameba")
      .repository_url("https://github.com/crystal-ameba/ameba")

    shard_version = ShardVersionBox.create &.shard_id(shard.id)
      .version("1.0.0")
      .released_at(Time.utc)

    worker = IndexShardWorker.new(
      shard_name: "ameba",
      version: "1.0.0"
    )

    worker.perform

    shard_after = ShardQuery.new.name("ameba").first

    shard_after.github_stars.should_not be_nil
    shard_after.last_synced_at.should_not be_nil
  end
end
