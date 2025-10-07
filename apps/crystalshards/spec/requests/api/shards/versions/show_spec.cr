require "../../../../spec_helper"

describe Api::Shards::Versions::Show do
  it "returns 404 when shard not found" do
    response = ApiClient.exec(Api::Shards::Versions::Show.with(
      shard_name: "nonexistent",
      version_number: "0.1.0"
    ))

    response.status_code.should eq(404)
  end

  it "returns 404 when version not found" do
    shard = ShardFactory.create &.name("test-shard")

    response = ApiClient.exec(Api::Shards::Versions::Show.with(
      shard_name: "test-shard",
      version_number: "999.999.999"
    ))

    response.status_code.should eq(404)
  end

  it "returns version details with dependencies" do
    shard = ShardFactory.create &.name("test-shard")
      .description("A test shard")
      .repository_url("https://github.com/user/test-shard")
      .license("MIT")

    version = ShardVersionFactory.create &.shard_id(shard.id)
      .version("0.1.0")
      .released_at(Time.utc(2024, 1, 1))
      .commit_sha("abc123")

    dep = DependencyFactory.create &.shard_version_id(version.id)
      .name("dependency-shard")
      .version_requirement("~> 1.0")
      .scope("runtime")

    response = ApiClient.exec(Api::Shards::Versions::Show.with(
      shard_name: "test-shard",
      version_number: "0.1.0"
    ))

    response.should send_json(200)
    json = JSON.parse(response.body)
    json["shard_name"].should eq("test-shard")
    json["version"].should eq("0.1.0")
    json["commit_sha"].should eq("abc123")
    json["dependencies"].as_a.size.should eq(1)
    json["dependencies"][0]["name"].should eq("dependency-shard")
    json["dependencies"][0]["version_requirement"].should eq("~> 1.0")
    json["dependencies"][0]["scope"].should eq("runtime")
  end

  it "includes download count" do
    shard = ShardFactory.create &.name("test-shard")
    version = ShardVersionFactory.create &.shard_id(shard.id).version("0.1.0")

    3.times do
      DownloadFactory.create &.shard_version_id(version.id)
        .shard_id(shard.id)
        .ip_address("192.168.1.1")
        .user_agent("Test")
        .downloaded_at(Time.utc)
    end

    response = ApiClient.exec(Api::Shards::Versions::Show.with(
      shard_name: "test-shard",
      version_number: "0.1.0"
    ))

    response.should send_json(200)
    json = JSON.parse(response.body)
    json["downloads"].should eq(3)
  end
end
