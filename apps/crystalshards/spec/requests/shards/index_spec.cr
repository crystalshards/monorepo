require "../../spec_helper"

describe Shards::Index do
  it "renders browse page successfully" do
    response = BrowserClient.exec(Shards::Index)

    response.status_code.should eq(200)
    response.body.should contain("Browse Shards")
  end

  it "lists all shards" do
    shard1 = ShardFactory.create &.name("http-client")
    shard2 = ShardFactory.create &.name("json-parser")

    response = BrowserClient.exec(Shards::Index)

    response.status_code.should eq(200)
    response.body.should contain("http-client")
    response.body.should contain("json-parser")
  end

  it "searches shards by name" do
    shard1 = ShardFactory.create &.name("http-client")
    shard2 = ShardFactory.create &.name("database-orm")

    response = BrowserClient.exec(Shards::Index.with(query: "http"))

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

    response = BrowserClient.exec(Shards::Index.with(query: "HTTP"))

    response.status_code.should eq(200)
    response.body.should contain("awesome-lib")
    response.body.should_not contain("other-lib")
  end

  it "shows empty state when no shards found" do
    ShardFactory.create &.name("existing-shard")

    response = BrowserClient.exec(Shards::Index.with(query: "nonexistent"))

    response.status_code.should eq(200)
    response.body.should contain("No shards found matching your search")
    response.body.should contain("View All Shards")
  end

  it "displays search results count" do
    3.times do |i|
      ShardFactory.create &.name("test-shard-#{i}")
    end

    response = BrowserClient.exec(Shards::Index.with(query: "test"))

    response.status_code.should eq(200)
    response.body.should contain("Found 3 shards")
  end

  it "handles pagination" do
    25.times do |i|
      ShardFactory.create &.name("shard-#{i}")
    end

    response = BrowserClient.exec(Shards::Index.with(page: 1))

    response.status_code.should eq(200)
    response.body.should contain("Next")
    response.body.should contain("Page 1 of 2")
  end

  it "shows previous link on page 2" do
    25.times do |i|
      ShardFactory.create &.name("shard-#{i}")
    end

    response = BrowserClient.exec(Shards::Index.with(page: 2))

    response.status_code.should eq(200)
    response.body.should contain("Previous")
    response.body.should contain("Page 2 of 2")
  end

  it "orders shards by most recently updated" do
    old_shard = ShardFactory.create &.name("old-shard")
      .updated_at(2.days.ago)
    new_shard = ShardFactory.create &.name("new-shard")
      .updated_at(1.hour.ago)

    response = BrowserClient.exec(Shards::Index)

    response.status_code.should eq(200)
    new_position = response.body.index("new-shard")
    old_position = response.body.index("old-shard")

    new_position.should_not be_nil
    old_position.should_not be_nil
    new_position.not_nil!.should be < old_position.not_nil!
  end

  it "includes search bar with current query" do
    response = BrowserClient.exec(Shards::Index.with(query: "http"))

    response.status_code.should eq(200)
    response.body.should contain("value=\"http\"")
  end

  it "displays shard metadata in cards, with dependents and no downloads" do
    target = ShardFactory.create &.name("test-shard")
      .description("A test shard")
      .github_stars(42)
      .total_downloads(100)
      .license("MIT")

    depender = ShardFactory.create &.name("depending-shard")
    version = ShardVersionFactory.create &.shard_id(depender.id)
    DependencyFactory.create &.shard_version_id(version.id).dependent_shard_id(target.id)

    response = BrowserClient.exec(Shards::Index)

    response.status_code.should eq(200)
    response.body.should contain("test-shard")
    response.body.should contain("A test shard")
    # The unit is a visually-hidden label beside the figure, so assert on both
    # rather than on one contiguous string.
    response.body.should contain("42")
    response.body.should contain("stars")
    response.body.should contain("dependents")
    response.body.should contain("MIT")

    # Positive control for the negative assertion below: this row still
    # carries total_downloads 100, so a renderer that had kept the figure
    # would have had something to print and this would fail.
    response.body.downcase.should_not contain("download")
  end

  it "distinguishes an unfetched star count from a measured zero" do
    ShardFactory.create &.name("never-fetched")
    ShardFactory.create &.name("measured-at-zero").github_stars(0)

    response = BrowserClient.exec(Shards::Index)

    response.status_code.should eq(200)
    # The unfetched shard says so instead of claiming zero stars.
    response.body.should contain("not indexed")
    response.body.should contain("stat-unknown")
  end

  describe "sorting" do
    it "sorts by popularity (GitHub stars)" do
      unpopular = ShardFactory.create &.name("unpopular").github_stars(10)
      popular = ShardFactory.create &.name("popular").github_stars(1000)

      response = BrowserClient.exec(Shards::Index.with(sort: "popular"))

      response.status_code.should eq(200)
      popular_index = response.body.index("popular")
      unpopular_index = response.body.index("unpopular")

      popular_index.should_not be_nil
      unpopular_index.should_not be_nil
      popular_index.not_nil!.should be < unpopular_index.not_nil!
    end

    it "sorts by name alphabetically" do
      z_shard = ShardFactory.create &.name("zulu-shard")
      a_shard = ShardFactory.create &.name("alpha-shard")
      m_shard = ShardFactory.create &.name("middle-shard")

      response = BrowserClient.exec(Shards::Index.with(sort: "name"))

      response.status_code.should eq(200)
      alpha_index = response.body.index("alpha-shard")
      middle_index = response.body.index("middle-shard")
      zulu_index = response.body.index("zulu-shard")

      alpha_index.should_not be_nil
      middle_index.should_not be_nil
      zulu_index.should_not be_nil
      alpha_index.not_nil!.should be < middle_index.not_nil!
      middle_index.not_nil!.should be < zulu_index.not_nil!
    end

    it "sorts by dependents" do
      ignored = ShardFactory.create &.name("ignored-shard")
      depended = ShardFactory.create &.name("depended-shard")
      depender = ShardFactory.create &.name("depender-shard")
      version = ShardVersionFactory.create &.shard_id(depender.id)
      DependencyFactory.create &.shard_version_id(version.id).dependent_shard_id(depended.id)

      response = BrowserClient.exec(Shards::Index.with(sort: "dependents"))

      response.status_code.should eq(200)
      response.body.index("depended-shard").not_nil!
        .should be < response.body.index("ignored-shard").not_nil!
    end

    it "keeps an old downloads sort working by falling back to popularity" do
      quiet = ShardFactory.create &.name("quiet-shard").github_stars(2)
      loved = ShardFactory.create &.name("loved-shard").github_stars(4000)

      response = BrowserClient.exec(Shards::Index.with(sort: "downloads"))

      response.status_code.should eq(200)
      response.body.index("loved-shard").not_nil!
        .should be < response.body.index("quiet-shard").not_nil!
    end

    it "defaults to popularity rather than crawl order" do
      # The crawler walks GitHub search bisected on shard.yml byte size, so
      # every row arrived in one burst and recency is very nearly crawl order,
      # which puts the smallest manifests on the internet first.
      quiet = ShardFactory.create &.name("quiet-shard").github_stars(2)
      loved = ShardFactory.create &.name("loved-shard").github_stars(4000)

      response = BrowserClient.exec(Shards::Index)

      response.status_code.should eq(200)
      response.body.index("loved-shard").not_nil!
        .should be < response.body.index("quiet-shard").not_nil!
    end

    it "offers no downloads option in the sort dropdown" do
      response = BrowserClient.exec(Shards::Index)

      response.status_code.should eq(200)
      # Positive control: the replacement options ARE found in the same body.
      response.body.should contain("Most Depended On")
      response.body.should contain("Most Stars")
      response.body.downcase.should_not contain("download")
    end
  end

  describe "filtering" do
    it "filters by license" do
      mit_shard = ShardFactory.create &.name("mit-shard").license("MIT")
      apache_shard = ShardFactory.create &.name("apache-shard").license("Apache-2.0")
      bsd_shard = ShardFactory.create &.name("bsd-shard").license("BSD-3-Clause")

      response = BrowserClient.exec(Shards::Index.with(license: "MIT"))

      response.status_code.should eq(200)
      response.body.should contain("mit-shard")
      response.body.should_not contain("apache-shard")
      response.body.should_not contain("bsd-shard")
    end

    it "filters by minimum stars" do
      low_stars = ShardFactory.create &.name("low-stars").github_stars(5)
      medium_stars = ShardFactory.create &.name("medium-stars").github_stars(75)
      high_stars = ShardFactory.create &.name("high-stars").github_stars(200)

      response = BrowserClient.exec(Shards::Index.with(min_stars: 50))

      response.status_code.should eq(200)
      response.body.should_not contain("low-stars")
      response.body.should contain("medium-stars")
      response.body.should contain("high-stars")
    end

    it "filters by has documentation" do
      with_docs = ShardFactory.create &.name("with-docs").documentation_url("https://docs.example.com")
      without_docs = ShardFactory.create &.name("without-docs").documentation_url(nil)

      response = BrowserClient.exec(Shards::Index.with(has_docs: true))

      response.status_code.should eq(200)
      response.body.should contain("with-docs")
      response.body.should_not contain("without-docs")
    end

    it "combines multiple filters" do
      matching = ShardFactory.create &.name("matching-shard")
        .license("MIT")
        .github_stars(100)
        .documentation_url("https://docs.example.com")

      not_matching_license = ShardFactory.create &.name("wrong-license")
        .license("Apache-2.0")
        .github_stars(100)
        .documentation_url("https://docs.example.com")

      not_matching_stars = ShardFactory.create &.name("low-stars")
        .license("MIT")
        .github_stars(10)
        .documentation_url("https://docs.example.com")

      not_matching_docs = ShardFactory.create &.name("no-docs")
        .license("MIT")
        .github_stars(100)
        .documentation_url(nil)

      response = BrowserClient.exec(Shards::Index.with(
        license: "MIT",
        min_stars: 50,
        has_docs: true
      ))

      response.status_code.should eq(200)
      response.body.should contain("matching-shard")
      response.body.should_not contain("wrong-license")
      response.body.should_not contain("low-stars")
      response.body.should_not contain("no-docs")
    end

    it "shows clear filters button when filters active" do
      ShardFactory.create &.name("test")

      response = BrowserClient.exec(Shards::Index.with(license: "MIT"))

      response.status_code.should eq(200)
      response.body.should contain("Clear Filters")
    end

    it "maintains filters across pagination" do
      # Create 25 MIT shards and 5 Apache shards
      25.times do |i|
        ShardFactory.create &.name("mit-#{i}").license("MIT")
      end
      5.times do |i|
        ShardFactory.create &.name("apache-#{i}").license("Apache-2.0")
      end

      response = BrowserClient.exec(Shards::Index.with(license: "MIT", page: 2))

      response.status_code.should eq(200)
      response.body.should contain("Page 2")
      # Verify pagination links preserve filters
      response.body.should contain("license=MIT")
    end

    it "combines filters with search query" do
      # Repository URLs are set explicitly here because search also matches the
      # canonical identity: the factory's default URL lives under
      # github.com/crystal-lang, which would make every shard match "crystal".
      matching = ShardFactory.create &.name("crystal-db")
        .repository_url("https://github.com/someone/crystal-db")
        .license("MIT")
        .github_stars(100)

      not_matching_query = ShardFactory.create &.name("other-lib")
        .repository_url("https://github.com/someone/other-lib")
        .description("Database library for PostgreSQL")
        .license("MIT")
        .github_stars(100)

      not_matching_license = ShardFactory.create &.name("crystal-http")
        .repository_url("https://github.com/someone/crystal-http")
        .license("Apache-2.0")
        .github_stars(100)
      response = BrowserClient.exec(Shards::Index.with(
        query: "crystal",
        license: "MIT",
        min_stars: 50
      ))

      response.status_code.should eq(200)
      response.body.should contain("crystal-db")
      response.body.should_not contain("other-lib")
      response.body.should_not contain("crystal-http")
    end

    it "combines filters with sorting" do
      apache = ShardFactory.create &.name("high-apache")
        .license("Apache-2.0")
        .github_stars(10000)

      low_mit = ShardFactory.create &.name("low-mit")
        .license("MIT")
        .github_stars(100)

      high_mit = ShardFactory.create &.name("high-mit")
        .license("MIT")
        .github_stars(5000)

      response = BrowserClient.exec(Shards::Index.with(
        license: "MIT",
        sort: "stars"
      ))

      response.status_code.should eq(200)
      response.body.should_not contain("high-apache")
      response.body.should contain("high-mit")
      response.body.should contain("low-mit")

      # Verify sorting order
      high_index = response.body.index("high-mit")
      low_index = response.body.index("low-mit")
      high_index.should_not be_nil
      low_index.should_not be_nil
      high_index.not_nil!.should be < low_index.not_nil!
    end
  end

  describe "filters UI" do
    it "displays filters section" do
      response = BrowserClient.exec(Shards::Index)

      response.status_code.should eq(200)
      response.body.should contain("Sort by:")
      response.body.should contain("License:")
      response.body.should contain("Min Stars:")
      response.body.should contain("Has Documentation")
      response.body.should contain("Apply Filters")
    end

    it "preserves selected sort option" do
      ShardFactory.create &.name("test")

      response = BrowserClient.exec(Shards::Index.with(sort: "popular"))

      response.status_code.should eq(200)
      response.body.should contain("Most Popular")
      response.body.should contain("selected")
    end

    it "preserves selected license filter" do
      ShardFactory.create &.name("test")

      response = BrowserClient.exec(Shards::Index.with(license: "MIT"))

      response.status_code.should eq(200)
      response.body.should contain("MIT")
    end

    it "preserves checked has_docs checkbox" do
      ShardFactory.create &.name("test").documentation_url("https://docs.example.com")

      response = BrowserClient.exec(Shards::Index.with(has_docs: true))

      response.status_code.should eq(200)
      response.body.should contain("checked")
    end
  end

  # Every shard links to its documentation, from the listing as well as from
  # its own page, because the link is what causes the documentation to be
  # built.
  describe "documentation links" do
    it "links a listed shard to its documentation" do
      shard = ShardFactory.create &.name("listed")
        .host("github.com").owner("acme").repo("listed")
        .canonical_slug("github.com/acme/listed")

      response = BrowserClient.exec(Shards::Index)

      response.body.should contain(CrystalShards::DocsSite.url_for?(shard).not_nil!)
    end

    it "gives two same-named shards two different documentation links" do
      ShardFactory.create &.name("router")
        .host("github.com").owner("acme").repo("router")
        .canonical_slug("github.com/acme/router")
      ShardFactory.create &.name("router")
        .host("gitlab.com").owner("acme").repo("router")
        .canonical_slug("gitlab.com/acme/router")

      response = BrowserClient.exec(Shards::Index)

      response.body.should contain("https://crystaldocs.org/docs/_/github.com/acme/router")
      response.body.should contain("https://crystaldocs.org/docs/_/gitlab.com/acme/router")
    end

    # No identity, no key, no URL. Guessing one from the name would point at
    # whichever repository claimed it.
    it "links nowhere for a shard whose repository could not be identified" do
      insert_unidentified_shard("unidentified")

      response = BrowserClient.exec(Shards::Index)

      response.body.should contain("unidentified")
      response.body.should_not contain("crystaldocs.org/docs/unidentified")
    end
  end
end
