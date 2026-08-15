require "../../spec_helper"

describe Home::Index do
  it "shows the homepage with stats" do
    doc1 = DocFactory.create &.package_name("http-client")
      .description("HTTP client library")
      .total_views(100)

    doc2 = DocFactory.create &.package_name("database")
      .description("Database ORM")
      .total_views(50)

    response = BrowserClient.exec(Home::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("CrystalDocs")
    response.body.should contain("Crystal Shard Documentation")
  end

  # The landing page counts the ecosystem from the registry and its own builds
  # from its own tables, and says which is which. It used to report the `docs`
  # row count as "Packages", which counted the packages somebody had opened
  # here and disagreed with crystalshards for the same set of shards.
  it "counts packages from the registry and versions from its own builds" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .publish("github.com/luckyframework/lucky", "lucky")
      .publish("github.com/amberframework/amber", "amber")
      .install

    doc = DocFactory.create &.package_name("github.com/kemalcr/kemal")
    DocVersionFactory.create &.doc_id(doc.id).version("1.6.0").build_status("success")
    DocVersionFactory.create &.doc_id(doc.id).version("1.5.0").build_status("pending")

    response = BrowserClient.exec(Home::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Packages")
    response.body.should contain("3")
    # One built version, not the two rows: a pending row is a package somebody
    # asked for, not documentation this site has.
    response.body.should contain("Built versions")
    response.body.should contain("<dd>1</dd>")
  end

  # No number at all beats this app's own row count wearing the label
  # "Packages", which is a fraction of the ecosystem presented as all of it.
  it "prints no package count when the registry cannot be reached" do
    DocFactory.create_pair

    StubRegistryPackages.new(reachable: false).install

    response = BrowserClient.exec(Home::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should_not contain("Packages</dt>")
    response.body.should contain("Built versions")
  end

  it "shows recently updated documentation" do
    recent_doc = DocFactory.create &.package_name("recent-shard")
      .last_updated_at(Time.utc - 1.hour)

    old_doc = DocFactory.create &.package_name("old-shard")
      .last_updated_at(Time.utc - 30.days)

    response = BrowserClient.exec(Home::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Recently Updated")
  end

  it "shows popular documentation" do
    popular_doc = DocFactory.create &.package_name("popular-shard")
      .total_views(1000)

    unpopular_doc = DocFactory.create &.package_name("unpopular-shard")
      .total_views(10)

    response = BrowserClient.exec(Home::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("Popular Packages")
  end

  it "handles empty state gracefully" do
    response = BrowserClient.exec(Home::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("No documentation available yet")
  end

  # The footer carries the collective's mark, a line naming the collective
  # as this site's maintainer, this repository's license, and a link to each
  # sibling site. The cross links are asserted against SiteLinks.origin
  # rather than a literal hostname, so this fails the way it should if the
  # footer ever goes back to a hardcoded URL: the spec default is a
  # localhost origin, and a hardcoded production hostname would not match
  # it.
  it "renders the Bushido Collective seal, maintainer line, license, and cross links" do
    response = BrowserClient.exec(Home::Index)

    response.body.should contain(%(class="tbc-seal"))
    response.body.should contain(%(aria-label="Forged by The Bushido Collective"))
    response.body.should contain("https://thebushido.co")
    response.body.should contain("The Bushido Collective builds and maintains this site.")

    response.body.should contain("Apache License 2.0")
    response.body.should contain("https://github.com/crystalshards/monorepo/blob/main/LICENSE")

    response.body.should contain(SiteLinks.origin(:crystalshards))
    response.body.should contain(SiteLinks.origin(:crystalgigs))
    response.body.should contain(SiteLinks.origin(:crystalbits))
  end
end
