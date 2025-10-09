require "../../spec_helper"

describe Shards::Index do
  it "renders browse page successfully" do
    response = ApiClient.exec(Shards::Index)

    response.status_code.should eq(200)
    response.body.should contain("Browse Shards")
  end

  it "lists all shards" do
    shard1 = ShardFactory.create &.name("http-client")
    shard2 = ShardFactory.create &.name("json-parser")

    response = ApiClient.exec(Shards::Index)

    response.status_code.should eq(200)
    response.body.should contain("http-client")
    response.body.should contain("json-parser")
  end

  it "searches shards by name" do
    shard1 = ShardFactory.create &.name("http-client")
    shard2 = ShardFactory.create &.name("database-orm")

    response = ApiClient.exec(Shards::Index.with(query: "http"))

    response.status_code.should eq(200)
    response.body.should contain("http-client")
    response.body.should_not contain("database-orm")
    response.body.should contain("Found 1 shard")
  end

  it "searches shards by description" do
    shard1 = ShardFactory.create &.name("awesome-lib")
      .description("HTTP client library")
    shard2 = ShardFactory.create &.name("other-lib")
      .description("Database connector")

    response = ApiClient.exec(Shards::Index.with(query: "HTTP"))

    response.status_code.should eq(200)
    response.body.should contain("awesome-lib")
    response.body.should_not contain("other-lib")
  end

  it "shows empty state when no shards found" do
    ShardFactory.create &.name("existing-shard")

    response = ApiClient.exec(Shards::Index.with(query: "nonexistent"))

    response.status_code.should eq(200)
    response.body.should contain("No shards found matching your search")
    response.body.should contain("View All Shards")
  end

  it "displays search results count" do
    3.times do |i|
      ShardFactory.create &.name("test-shard-#{i}")
    end

    response = ApiClient.exec(Shards::Index.with(query: "test"))

    response.status_code.should eq(200)
    response.body.should contain("Found 3 shards")
  end

  it "handles pagination" do
    25.times do |i|
      ShardFactory.create &.name("shard-#{i}")
    end

    response = ApiClient.exec(Shards::Index.with(page: 1))

    response.status_code.should eq(200)
    response.body.should contain("Next")
    response.body.should contain("Page 1 of 2")
  end

  it "shows previous link on page 2" do
    25.times do |i|
      ShardFactory.create &.name("shard-#{i}")
    end

    response = ApiClient.exec(Shards::Index.with(page: 2))

    response.status_code.should eq(200)
    response.body.should contain("Previous")
    response.body.should contain("Page 2 of 2")
  end

  it "orders shards by most recently updated" do
    old_shard = ShardFactory.create &.name("old-shard")
      .updated_at(2.days.ago)
    new_shard = ShardFactory.create &.name("new-shard")
      .updated_at(1.hour.ago)

    response = ApiClient.exec(Shards::Index)

    response.status_code.should eq(200)
    new_position = response.body.index("new-shard")
    old_position = response.body.index("old-shard")

    new_position.should_not be_nil
    old_position.should_not be_nil
    new_position.not_nil!.should be < old_position.not_nil!
  end

  it "includes search bar with current query" do
    response = ApiClient.exec(Shards::Index.with(query: "http"))

    response.status_code.should eq(200)
    response.body.should contain("value=\"http\"")
  end

  it "displays shard metadata in cards" do
    shard = ShardFactory.create &.name("test-shard")
      .description("A test shard")
      .github_stars(42)
      .total_downloads(100)
      .license("MIT")

    response = ApiClient.exec(Shards::Index)

    response.status_code.should eq(200)
    response.body.should contain("test-shard")
    response.body.should contain("A test shard")
    response.body.should contain("42")
    response.body.should contain("100 downloads")
    response.body.should contain("MIT")
  end
end
