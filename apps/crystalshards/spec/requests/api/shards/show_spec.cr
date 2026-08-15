require "../../../spec_helper"

describe Api::Shards::Show do
  it "returns 404 when shard not found" do
    response = ApiClient.exec(Api::Shards::Show.with(**unregistered_identity))

    response.status.should eq(HTTP::Status::NOT_FOUND)
  end

  it "returns shard details with versions" do
    shard = ShardFactory.create &.name("test-shard")
      .description("A test shard")
      .repository_url("https://github.com/user/test-shard")
      .license("MIT")

    version = ShardVersionFactory.create &.shard_id(shard.id)
      .version("0.1.0")
      .released_at(Time.utc)

    response = ApiClient.exec(Api::Shards::Show.with(**identity_of(shard)))

    response.status.should eq(HTTP::Status.new(200))
    json = JSON.parse(response.body)
    json["name"].should eq("test-shard")
    json["description"].should eq("A test shard")
    json["license"].should eq("MIT")
    json["versions"].as_a.size.should eq(1)
    json["versions"][0]["version"].should eq("0.1.0")
  end

  it "never includes an author's address, even when an indexed version's manifest carries one" do
    shard = ShardFactory.create &.name("test-shard")
    ShardVersionFactory.create &.shard_id(shard.id)
      .version("0.1.0")
      .metadata(JSON.parse(%({"authors": ["Ary Borenszweig <ary@example.com>"]})))

    response = ApiClient.exec(Api::Shards::Show.with(**identity_of(shard)))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should_not contain("ary@example.com")
    response.body.should_not contain("@example.com")
  end
end
