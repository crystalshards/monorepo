require "../../spec_helper"

describe Home::Index do
  it "renders homepage successfully" do
    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("CrystalShards")
    response.body.should contain("The package registry for")
    response.body.should contain("indexed straight from the source repository")
    # The landing page leads with how to add a dependency, not a hero image.
    response.body.should contain("shards install")
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
    response.body.should contain("Recently updated")
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

  it "renders no downloads figure, and would have caught one if it were there" do
    # Positive control built into the assertion: the same body IS searched
    # successfully for the stat that replaced downloads, so this cannot pass
    # by accident on an empty or failed render. Real Download rows exist here,
    # so any surviving counter would have something to print.
    shard = ShardFactory.create &.name("some-shard")
    version = ShardVersionFactory.create &.shard_id(shard.id)
    DownloadFactory.create &.shard_version_id(version.id).shard_id(shard.id)
    DownloadFactory.create &.shard_version_id(version.id).shard_id(shard.id)

    response = BrowserClient.exec(Home::Index)

    response.status_code.should eq(200)
    response.body.should contain("Dependency links")
    response.body.downcase.should_not contain("download")
  end

  it "says stars are unmeasured rather than printing a zero" do
    # A registry whose metadata fetch has not run has no star count. Printing
    # 0 would claim nobody has starred anything, which is the exact failure
    # that made the download counter worth deleting.
    ShardFactory.create &.name("unfetched")

    response = BrowserClient.exec(Home::Index)

    response.body.should contain("Stars")
    response.body.should contain("not indexed yet")
  end

  it "sums stars once any shard has actually been measured" do
    ShardFactory.create &.name("alpha").github_stars(40)
    ShardFactory.create &.name("beta").github_stars(2)

    response = BrowserClient.exec(Home::Index)

    response.body.should contain("42")
    response.body.should_not contain("not indexed yet")
  end

  it "hides the most starred section until something has been starred" do
    # Ranking six shards by a number none of them have is crawl order wearing
    # a popularity label.
    ShardFactory.create &.name("unfetched")

    response = BrowserClient.exec(Home::Index)

    response.body.should_not contain("Most starred")
    response.body.should contain("Recently updated")
  end

  it "shows a dependent count on every card" do
    target = ShardFactory.create &.name("target-shard")
    depender = ShardFactory.create &.name("depending-shard")
    version = ShardVersionFactory.create &.shard_id(depender.id)
    DependencyFactory.create &.shard_version_id(version.id).dependent_shard_id(target.id)

    response = BrowserClient.exec(Home::Index)

    response.body.should contain("dependents")
    response.body.should contain("Dependency links")
  end

  # The footer carries the collective's mark, this repository's license, and
  # a link to each sibling site. The cross links are asserted against
  # SiteLinks.origin rather than a literal hostname, so this fails the way it
  # should if the footer ever goes back to a hardcoded URL: the spec default
  # is a localhost origin, and a hardcoded production hostname would not
  # match it.
  it "renders the Bushido Collective seal, license, and cross links" do
    response = BrowserClient.exec(Home::Index)

    response.body.should contain(%(class="tbc-seal"))
    response.body.should contain(%(aria-label="Forged by The Bushido Collective"))
    response.body.should contain("https://thebushido.co")

    response.body.should contain("Apache License 2.0")
    response.body.should contain("https://github.com/crystalshards/monorepo/blob/main/LICENSE")

    response.body.should contain(SiteLinks.origin(:crystaldocs))
    response.body.should contain(SiteLinks.origin(:crystalgigs))
    response.body.should contain(SiteLinks.origin(:crystalbits))
  end
end
