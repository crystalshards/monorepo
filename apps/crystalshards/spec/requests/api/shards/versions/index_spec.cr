require "../../../../spec_helper"

describe Api::Shards::Versions::Index do
  it "returns 404 when shard not found" do
    response = ApiClient.exec(Api::Shards::Versions::Index.with(**unregistered_identity))

    response.status_code.should eq(404)
  end

  it "returns a shard's versions newest first, whatever order they were recorded in" do
    shard = ShardFactory.create &.name("test-shard")
      .description("A test shard")
      .repository_url("https://github.com/user/test-shard")
      .license("MIT")

    # Recorded in the order kemal's were: 64 tags in one pass, then the two
    # released afterwards, so insertion order and version order disagree and
    # the newest row is last in the table.
    ShardVersionFactory.create &.shard_id(shard.id)
      .version("1.11.0")
      .released_at(Time.utc(2024, 1, 1))

    ShardVersionFactory.create &.shard_id(shard.id)
      .version("1.13.0")
      .released_at(Time.utc(2024, 2, 1))

    ShardVersionFactory.create &.shard_id(shard.id)
      .version("1.2.0")
      .released_at(Time.utc(2024, 3, 1))

    response = ApiClient.exec(Api::Shards::Versions::Index.with(**identity_of(shard)))

    response.status.should eq(HTTP::Status.new(200))
    json = JSON.parse(response.body)
    json["name"].should eq("test-shard")
    json["versions"].as_a.map { |version| version["version"].as_s }.should eq(["1.13.0", "1.11.0", "1.2.0"])
  end

  it "includes download counts for each version" do
    shard = ShardFactory.create &.name("test-shard")
    version = ShardVersionFactory.create &.shard_id(shard.id).version("0.1.0")

    DownloadFactory.create &.shard_version_id(version.id)
      .shard_id(shard.id)
      .user_agent("Test")
      .downloaded_at(Time.utc)

    DownloadFactory.create &.shard_version_id(version.id)
      .shard_id(shard.id)
      .user_agent("Test")
      .downloaded_at(Time.utc)

    response = ApiClient.exec(Api::Shards::Versions::Index.with(**identity_of(shard)))

    response.status.should eq(HTTP::Status.new(200))
    json = JSON.parse(response.body)
    json["versions"][0]["downloads"].should eq(2)
  end
end
