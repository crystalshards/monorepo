require "../spec_helper"

describe ShardQuery do
  describe "#search" do
    it "finds shards by name" do
      http_shard = ShardFactory.create &.name("http-client")
      web_shard = ShardFactory.create &.name("web-framework")

      results = ShardQuery.new.search("http").results

      results.should contain(http_shard)
      results.should_not contain(web_shard)
    end

    it "finds shards by description" do
      shard = ShardFactory.create &.description("HTTP client library")
      other = ShardFactory.create &.description("Web framework")

      results = ShardQuery.new.search("HTTP").results

      results.should contain(shard)
      results.should_not contain(other)
    end

    it "is case insensitive" do
      shard = ShardFactory.create &.name("http-client")

      results = ShardQuery.new.search("HTTP").results

      results.should contain(shard)
    end

    it "returns all shards when query is nil" do
      ShardFactory.create_pair

      results = ShardQuery.new.search(nil).results

      results.size.should eq(2)
    end

    it "returns all shards when query is empty" do
      ShardFactory.create_pair

      results = ShardQuery.new.search("").results

      results.size.should eq(2)
    end
  end

  describe "#by_license" do
    it "filters shards by license" do
      mit_shard = ShardFactory.create &.license("MIT")
      apache_shard = ShardFactory.create &.license("Apache-2.0")

      results = ShardQuery.new.by_license("MIT").results

      results.should contain(mit_shard)
      results.should_not contain(apache_shard)
    end

    it "returns all when license is nil" do
      ShardFactory.create &.license("MIT")
      ShardFactory.create &.license("Apache-2.0")

      results = ShardQuery.new.by_license(nil).results

      results.size.should eq(2)
    end
  end

  describe "#with_min_stars" do
    it "filters shards with minimum stars" do
      popular = ShardFactory.create &.github_stars(100)
      unpopular = ShardFactory.create &.github_stars(10)

      results = ShardQuery.new.with_min_stars(50).results

      results.should contain(popular)
      results.should_not contain(unpopular)
    end

    it "includes shards with exactly min stars" do
      shard = ShardFactory.create &.github_stars(50)

      results = ShardQuery.new.with_min_stars(50).results

      results.should contain(shard)
    end

    it "returns all when min_stars is nil" do
      ShardFactory.create &.github_stars(100)
      ShardFactory.create &.github_stars(10)

      results = ShardQuery.new.with_min_stars(nil).results

      results.size.should eq(2)
    end
  end

  describe "#sort_by_column" do
    it "sorts by name ascending" do
      zebra = ShardFactory.create &.name("zebra")
      alpha = ShardFactory.create &.name("alpha")

      results = ShardQuery.new.sort_by_column("name", "asc").results

      results.first.should eq(alpha)
      results.last.should eq(zebra)
    end

    it "sorts by downloads descending" do
      popular = ShardFactory.create &.total_downloads(1000)
      unpopular = ShardFactory.create &.total_downloads(10)

      results = ShardQuery.new.sort_by_column("downloads", "desc").results

      results.first.should eq(popular)
      results.last.should eq(unpopular)
    end

    it "sorts by stars descending" do
      popular = ShardFactory.create &.github_stars(500)
      unpopular = ShardFactory.create &.github_stars(5)

      results = ShardQuery.new.sort_by_column("stars", "desc").results

      results.first.should eq(popular)
      results.last.should eq(unpopular)
    end

    it "sorts by updated descending by default" do
      old = ShardFactory.create
      sleep 0.01
      new_shard = ShardFactory.create

      results = ShardQuery.new.sort_by_column("updated", "desc").results

      results.first.id.should eq(new_shard.id)
      results.last.id.should eq(old.id)
    end

    it "uses default sort when column is invalid" do
      shard1 = ShardFactory.create
      shard2 = ShardFactory.create

      results = ShardQuery.new.sort_by_column("invalid", "desc").results

      results.size.should eq(2)
    end
  end

  describe "#paginate" do
    it "paginates results" do
      25.times { ShardFactory.create }

      page1 = ShardQuery.new.paginate(page: 1, per_page: 20).results
      page2 = ShardQuery.new.paginate(page: 2, per_page: 20).results

      page1.size.should eq(20)
      page2.size.should eq(5)
    end

    it "defaults to page 1 when page is less than 1" do
      ShardFactory.create_pair

      results = ShardQuery.new.paginate(page: 0, per_page: 20).results

      results.size.should eq(2)
    end
  end

  describe "chaining filters" do
    it "combines search and license filter" do
      mit_http = ShardFactory.create &.name("http-client").license("MIT")
      mit_web = ShardFactory.create &.name("web-framework").license("MIT")
      apache_http = ShardFactory.create &.name("http-server").license("Apache-2.0")

      results = ShardQuery.new
        .search("http")
        .by_license("MIT")
        .results

      results.should contain(mit_http)
      results.should_not contain(mit_web)
      results.should_not contain(apache_http)
    end

    it "combines multiple filters with sorting and pagination" do
      10.times do |i|
        ShardFactory.create &.name("shard-#{i}")
          .license("MIT")
          .github_stars(i * 10)
      end

      results = ShardQuery.new
        .by_license("MIT")
        .with_min_stars(30)
        .sort_by_column("stars", "desc")
        .paginate(page: 1, per_page: 5)
        .results

      results.size.should eq(5)
      results.first.github_stars.should eq(90)
    end
  end
end
