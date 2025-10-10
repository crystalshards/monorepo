require "../../spec_helper"

describe Shards::Index do
  it "displays all shards by default" do
    shard1 = ShardFactory.create &.name("shard-one")
    shard2 = ShardFactory.create &.name("shard-two")

    response = ApiClient.exec(Shards::Index)

    response.status.should eq(200)
    response.body.should contain(shard1.name)
    response.body.should contain(shard2.name)
  end

  it "filters shards by search query" do
    http_shard = ShardFactory.create &.name("http-client")
    web_shard = ShardFactory.create &.name("web-framework")

    response = ApiClient.exec(Shards::Index, query: "http")

    response.status.should eq(200)
    response.body.should contain(http_shard.name)
    response.body.should_not contain(web_shard.name)
  end

  it "filters shards by license" do
    mit_shard = ShardFactory.create &.name("mit-shard").license("MIT")
    apache_shard = ShardFactory.create &.name("apache-shard").license("Apache-2.0")

    response = ApiClient.exec(Shards::Index, license: "MIT")

    response.status.should eq(200)
    response.body.should contain(mit_shard.name)
    response.body.should_not contain(apache_shard.name)
  end

  it "filters shards by minimum stars" do
    popular = ShardFactory.create &.name("popular").github_stars(100)
    unpopular = ShardFactory.create &.name("unpopular").github_stars(10)

    response = ApiClient.exec(Shards::Index, min_stars: "50")

    response.status.should eq(200)
    response.body.should contain(popular.name)
    response.body.should_not contain(unpopular.name)
  end

  it "sorts shards by name" do
    zebra = ShardFactory.create &.name("zebra")
    alpha = ShardFactory.create &.name("alpha")

    response = ApiClient.exec(Shards::Index, sort: "name")

    response.status.should eq(200)
    alpha_pos = response.body.index(alpha.name)
    zebra_pos = response.body.index(zebra.name)

    alpha_pos.should_not be_nil
    zebra_pos.should_not be_nil
    alpha_pos.should be < zebra_pos.not_nil! if alpha_pos
  end

  it "paginates results" do
    25.times { |i| ShardFactory.create &.name("shard-#{i}") }

    page1 = ApiClient.exec(Shards::Index, page: "1")
    page2 = ApiClient.exec(Shards::Index, page: "2")

    page1.status.should eq(200)
    page2.status.should eq(200)

    page1.body.should_not eq(page2.body)
  end

  it "combines multiple filters" do
    target = ShardFactory.create &.name("http-client").license("MIT").github_stars(100)
    wrong_name = ShardFactory.create &.name("web-framework").license("MIT").github_stars(100)
    wrong_license = ShardFactory.create &.name("http-server").license("Apache-2.0").github_stars(100)
    wrong_stars = ShardFactory.create &.name("http-lib").license("MIT").github_stars(10)

    response = ApiClient.exec(
      Shards::Index,
      query: "http",
      license: "MIT",
      min_stars: "50"
    )

    response.status.should eq(200)
    response.body.should contain(target.name)
    response.body.should_not contain(wrong_name.name)
    response.body.should_not contain(wrong_license.name)
    response.body.should_not contain(wrong_stars.name)
  end

  it "shows empty state when no results" do
    ShardFactory.create &.name("existing-shard")

    response = ApiClient.exec(Shards::Index, query: "nonexistent")

    response.status.should eq(200)
    response.body.should contain("No shards found")
  end

  it "shows total count in header" do
    3.times { ShardFactory.create }

    response = ApiClient.exec(Shards::Index)

    response.status.should eq(200)
    response.body.should contain("3")
  end
end
