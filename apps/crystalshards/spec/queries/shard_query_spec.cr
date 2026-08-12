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

    it "falls back to popularity for the retired downloads sort" do
      # Nothing is downloaded from this registry, so the ordering is gone. An
      # old bookmark carrying ?sort=downloads has to keep returning a sensible
      # page rather than erroring or falling into crawl order.
      quiet = ShardFactory.create &.name("quiet").github_stars(1)
      loved = ShardFactory.create &.name("loved").github_stars(900)

      results = ShardQuery.new.sort_by_column("downloads", "desc").results

      results.first.should eq(loved)
      results.last.should eq(quiet)
    end

    it "sorts by dependents, counting a depender with many releases once" do
      one_dependent = ShardFactory.create &.name("one-dependent")
      two_dependents = ShardFactory.create &.name("two-dependents")

      # A single depender that declares the same dependency across two
      # releases. Without DISTINCT this outweighs the shard below, which two
      # separate projects actually depend on.
      repeat = ShardFactory.create &.name("repeat-depender")
      repeat_v1 = ShardVersionFactory.create &.shard_id(repeat.id).version("1.0.0")
      repeat_v2 = ShardVersionFactory.create &.shard_id(repeat.id).version("2.0.0")
      DependencyFactory.create &.shard_version_id(repeat_v1.id).dependent_shard_id(one_dependent.id)
      DependencyFactory.create &.shard_version_id(repeat_v2.id).dependent_shard_id(one_dependent.id)
      DependencyFactory.create &.shard_version_id(repeat_v1.id).dependent_shard_id(two_dependents.id)

      other = ShardFactory.create &.name("other-depender")
      other_v1 = ShardVersionFactory.create &.shard_id(other.id).version("1.0.0")
      DependencyFactory.create &.shard_version_id(other_v1.id).dependent_shard_id(two_dependents.id)

      results = ShardQuery.new.sort_by_column("dependents", "desc").results

      results.index(&.id.==(two_dependents.id)).not_nil!
        .should be < results.index(&.id.==(one_dependent.id)).not_nil!
    end

    it "sorts shards with no star count last, not first" do
      # Postgres puts NULLs first on a DESC order. Without nulls_last a shard
      # nobody has fetched metadata for would lead "most stars".
      unmeasured = ShardFactory.create &.name("unmeasured")
      measured = ShardFactory.create &.name("measured").github_stars(3)

      results = ShardQuery.new.sort_by_column("stars", "desc").results

      results.first.id.should eq(measured.id)
      results.last.id.should eq(unmeasured.id)
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
      sleep 10.milliseconds
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
