require "../spec_helper"

describe BuildDocsWorker do
  pending "updates documentation_url after successful build" do
    shard = ShardFactory.create &.name("kemal")
      .repository_url("https://github.com/kemalcr/kemal")

    shard_version = ShardVersionFactory.create &.shard_id(shard.id)
      .version("1.0.0")
      .released_at(Time.utc)

    worker = BuildDocsWorker.new(
      shard_name: "kemal",
      version: "1.0.0"
    )

    worker.perform

    shard_after = ShardQuery.new.name("kemal").first?
    shard_after.not_nil!.documentation_url.should_not be_nil
    shard_after.not_nil!.documentation_url.should contain("crystaldocs.org")
  end

  pending "handles non-existent shards gracefully" do
    worker = BuildDocsWorker.new(
      shard_name: "nonexistent",
      version: "1.0.0"
    )

    expect_raises(Exception) do
      worker.perform
    end
  end

  pending "handles repositories without buildable docs" do
    shard = ShardFactory.create &.name("test-shard")
      .repository_url("https://github.com/user/empty-repo")

    shard_version = ShardVersionFactory.create &.shard_id(shard.id)
      .version("1.0.0")
      .released_at(Time.utc)

    worker = BuildDocsWorker.new(
      shard_name: "test-shard",
      version: "1.0.0"
    )

    worker.perform

    shard_after = ShardQuery.new.name("test-shard").first?
    shard_after.not_nil!.documentation_url.should be_nil
  end
end
