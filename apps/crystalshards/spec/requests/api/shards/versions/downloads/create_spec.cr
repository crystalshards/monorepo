require "../../../../../spec_helper"

describe Api::Shards::Versions::Downloads::Create do
  it "returns 404 when shard not found" do
    response = ApiClient.exec(Api::Shards::Versions::Downloads::Create.with(
      shard_name: "nonexistent",
      version_number: "0.1.0"
    ))

    response.status.should eq(404)
  end

  it "returns 404 when version not found" do
    shard = ShardBox.create &.name("test-shard")

    response = ApiClient.exec(Api::Shards::Versions::Downloads::Create.with(
      shard_name: "test-shard",
      version_number: "999.999.999"
    ))

    response.status.should eq(404)
  end

  it "returns 410 when version is yanked" do
    shard = ShardBox.create &.name("test-shard")
    version = ShardVersionBox.create &.shard_id(shard.id)
      .version("0.1.0")
      .yanked(true)

    response = ApiClient.exec(Api::Shards::Versions::Downloads::Create.with(
      shard_name: "test-shard",
      version_number: "0.1.0"
    ))

    response.status.should eq(410)
    json = JSON.parse(response.body)
    json["error"].as_s.should contain("yanked")
  end

  it "tracks download and increments counters" do
    shard = ShardBox.create &.name("test-shard").total_downloads(0)
    version = ShardVersionBox.create &.shard_id(shard.id).version("0.1.0")

    initial_download_count = DownloadQuery.new.shard_version_id(version.id).count

    response = ApiClient.exec(Api::Shards::Versions::Downloads::Create.with(
      shard_name: "test-shard",
      version_number: "0.1.0"
    ))

    response.should send_json(200)
    json = JSON.parse(response.body)
    json["message"].as_s.should contain("tracked successfully")

    DownloadQuery.new.shard_version_id(version.id).count.should eq(initial_download_count + 1)

    updated_shard = ShardQuery.new.id(shard.id).first!
    updated_shard.total_downloads.should eq(1)
  end

  it "captures request metadata" do
    shard = ShardBox.create &.name("test-shard")
    version = ShardVersionBox.create &.shard_id(shard.id).version("0.1.0")

    response = ApiClient.exec(Api::Shards::Versions::Downloads::Create.with(
      shard_name: "test-shard",
      version_number: "0.1.0"
    ))

    response.should send_json(200)

    download = DownloadQuery.new.shard_version_id(version.id).first!
    download.ip_address.should_not be_nil
    download.user_agent.should_not be_nil
    download.downloaded_at.should_not be_nil
  end
end
