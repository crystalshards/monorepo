require "../../../../spec_helper"

describe Api::Shards::Versions::Index do
  it "returns 404 when shard not found" do
    response = ApiClient.exec(Api::Shards::Versions::Index.with(**unregistered_identity))

    response.status_code.should eq(404)
  end

  it "returns list of versions for a shard" do
    shard = ShardFactory.create &.name("test-shard")
      .description("A test shard")
      .repository_url("https://github.com/user/test-shard")
      .license("MIT")

    version1 = ShardVersionFactory.create &.shard_id(shard.id)
      .version("0.1.0")
      .released_at(Time.utc(2024, 1, 1))

    version2 = ShardVersionFactory.create &.shard_id(shard.id)
      .version("0.2.0")
      .released_at(Time.utc(2024, 2, 1))

    response = ApiClient.exec(Api::Shards::Versions::Index.with(**identity_of(shard)))

    response.status.should eq(HTTP::Status.new(200))
    json = JSON.parse(response.body)
    json["name"].should eq("test-shard")
    json["versions"].as_a.size.should eq(2)
    json["versions"][0]["version"].should eq("0.1.0")
    json["versions"][1]["version"].should eq("0.2.0")
  end

  it "includes download counts for each version" do
    shard = ShardFactory.create &.name("test-shard")
    version = ShardVersionFactory.create &.shard_id(shard.id).version("0.1.0")

    DownloadFactory.create &.shard_version_id(version.id)
      .shard_id(shard.id)
      .ip_address("192.168.1.1")
      .user_agent("Test")
      .downloaded_at(Time.utc)

    DownloadFactory.create &.shard_version_id(version.id)
      .shard_id(shard.id)
      .ip_address("192.168.1.2")
      .user_agent("Test")
      .downloaded_at(Time.utc)

    response = ApiClient.exec(Api::Shards::Versions::Index.with(**identity_of(shard)))

    response.status.should eq(HTTP::Status.new(200))
    json = JSON.parse(response.body)
    json["versions"][0]["downloads"].should eq(2)
  end
end
