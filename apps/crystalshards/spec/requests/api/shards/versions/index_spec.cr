require "../../../../spec_helper"

describe Api::Shards::Versions::Index do
  it "returns 404 when shard not found" do
    response = ApiClient.exec(Api::Shards::Versions::Index.with(shard_name: "nonexistent"))

    response.status.should eq(404)
  end

  it "returns list of versions for a shard" do
    shard = ShardBox.create &.name("test-shard")
      .description("A test shard")
      .repository_url("https://github.com/user/test-shard")
      .license("MIT")

    version1 = ShardVersionBox.create &.shard_id(shard.id)
      .version("0.1.0")
      .released_at(Time.utc(2024, 1, 1))

    version2 = ShardVersionBox.create &.shard_id(shard.id)
      .version("0.2.0")
      .released_at(Time.utc(2024, 2, 1))

    response = ApiClient.exec(Api::Shards::Versions::Index.with(shard_name: "test-shard"))

    response.should send_json(200)
    json = JSON.parse(response.body)
    json["shard_name"].should eq("test-shard")
    json["versions"].as_a.size.should eq(2)
    json["versions"][0]["version"].should eq("0.1.0")
    json["versions"][1]["version"].should eq("0.2.0")
  end

  it "includes download counts for each version" do
    shard = ShardBox.create &.name("test-shard")
    version = ShardVersionBox.create &.shard_id(shard.id).version("0.1.0")

    DownloadBox.create &.shard_version_id(version.id)
      .ip_address("192.168.1.1")
      .user_agent("Test")
      .downloaded_at(Time.utc)

    DownloadBox.create &.shard_version_id(version.id)
      .ip_address("192.168.1.2")
      .user_agent("Test")
      .downloaded_at(Time.utc)

    response = ApiClient.exec(Api::Shards::Versions::Index.with(shard_name: "test-shard"))

    response.should send_json(200)
    json = JSON.parse(response.body)
    json["versions"][0]["downloads"].should eq(2)
  end
end
