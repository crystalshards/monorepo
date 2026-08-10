require "../../spec_helper"

describe Home::Index do
  it "renders homepage successfully" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("CrystalShards")
    response.body.should contain("Every shard, cut and")
    response.body.should contain("indexed straight from the source repository")
  end

  it "displays total shard count" do
    ShardFactory.create_pair

    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("2")
    response.body.should contain("shards")
  end

  it "displays featured shards sorted by GitHub stars" do
    shard1 = ShardFactory.create &.name("popular-shard").github_stars(100)
    shard2 = ShardFactory.create &.name("less-popular").github_stars(50)
    shard3 = ShardFactory.create &.name("unpopular").github_stars(10)

    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("popular-shard")
    response.body.should contain("less-popular")
  end

  it "displays recently updated shards" do
    old_shard = ShardFactory.create &.name("old-shard").updated_at(2.days.ago)
    new_shard = ShardFactory.create &.name("new-shard").updated_at(1.hour.ago)

    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("new-shard")
    response.body.should contain("Recently Updated")
  end

  it "includes search bar" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("search-input")
    response.body.should contain("Search")
  end

  it "handles empty state gracefully" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("0")
    response.body.should contain("shards")
  end

  it "displays total downloads count" do
    shard = ShardFactory.create
    version = ShardVersionFactory.create &.shard_id(shard.id)
    DownloadFactory.create &.shard_version_id(version.id).shard_id(shard.id)
    DownloadFactory.create &.shard_version_id(version.id).shard_id(shard.id)

    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("2")
    response.body.should contain("downloads")
  end
end
