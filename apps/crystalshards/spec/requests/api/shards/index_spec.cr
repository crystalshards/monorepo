require "../../../spec_helper"

describe Api::Shards::Index do
  it "returns empty array when no shards exist" do
    response = ApiClient.exec(Api::Shards::Index)

    response.should send_json(200, {shards: [] of String, meta: {page: 1, per_page: 20, total: 0}})
  end

  it "returns list of shards" do
    shard = ShardFactory.create &.name("test-shard")
      .description("A test shard")
      .repository_url("https://github.com/user/test-shard")

    response = ApiClient.exec(Api::Shards::Index)

    response.should send_json(200)
    response.body.should contain("test-shard")
    response.body.should contain("A test shard")
  end

  it "supports pagination" do
    25.times do |i|
      ShardFactory.create &.name("shard-#{i}")
        .repository_url("https://github.com/user/shard-#{i}")
    end

    response = ApiClient.exec(Api::Shards::Index.with(page: 2, per_page: 10))

    response.should send_json(200)
    json = JSON.parse(response.body)
    json["shards"].as_a.size.should eq(10)
    json["meta"]["page"].should eq(2)
  end

  it "supports search by name" do
    ShardFactory.create &.name("awesome-lib").repository_url("https://github.com/user/awesome-lib")
    ShardFactory.create &.name("cool-tool").repository_url("https://github.com/user/cool-tool")

    response = ApiClient.exec(Api::Shards::Index.with(query: "awesome"))

    response.should send_json(200)
    response.body.should contain("awesome-lib")
    response.body.should_not contain("cool-tool")
  end
end
