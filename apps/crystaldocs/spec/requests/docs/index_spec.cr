require "../../spec_helper"

# Browse lists the registry's shards, not this app's rows.
#
# The rows were the bug. A `docs` row is written by `PackageRegistration` the
# first time somebody opens a package's version URL and by nothing else, so
# browsing them listed the packages this site had been asked for and reported
# that count as the size of the ecosystem. crystalshards said 4,921 and
# crystaldocs said a couple of dozen, for the same set of shards.
describe Docs::Index do
  it "lists the registry's packages, including ones nobody has built" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"])
      .publish("github.com/luckyframework/lucky", "lucky", ["1.5.0"])
      .install

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should contain("github.com/kemalcr/kemal")
    response.body.should contain("github.com/luckyframework/lucky")
  end

  # The point of the change. A package the registry has and this app has never
  # heard of is listable, and the card says which it is rather than pretending
  # there is documentation behind the link.
  it "lists a registry package with no local row at all" do
    StubRegistryPackages.new
      .publish("github.com/tunkshif/lsp", "lsp", ["0.1.0"])
      .install

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should contain("github.com/tunkshif/lsp")
    response.body.should contain("Not built yet")
  end

  # A registry package with a `docs` row whose versions are all still pending
  # is not documented either. The row only proves somebody asked.
  it "counts a registered but unbuilt package as not built" do
    doc = DocFactory.create &.package_name("github.com/kemalcr/kemal")
      .current_version("1.6.0")
    DocVersionFactory.create &.doc_id(doc.id).version("1.6.0").build_status("pending")

    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"])
      .install

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should contain("Not built yet")
  end

  it "shows build state for a package this app has documented" do
    doc = DocFactory.create &.package_name("github.com/kemalcr/kemal")
      .current_version("1.6.0")
      .total_views(42)
    DocVersionFactory.create &.doc_id(doc.id).version("1.6.0").build_status("success")

    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"])
      .install

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should contain("42 views")
    response.body.should_not contain("Not built yet")
  end

  # A local row for a package the registry does not have is not in the
  # catalogue. Those rows are build state; the registry decides what exists.
  it "does not list a local row the registry has no shard for" do
    DocFactory.create &.package_name("invented-package")

    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .install

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should_not contain("invented-package")
  end

  it "searches the registry by shard name" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .publish("github.com/crystal-lang/crystal-db", "db")
      .install

    response = BrowserClient.exec(Docs::Index.with(query: "kemal"))

    response.status_code.should eq(200)
    response.body.should contain("kemal")
    response.body.should_not contain("crystal-lang/crystal-db")
  end

  # The slug is what the card shows and what a reader types back in.
  it "searches the registry by repository slug" do
    StubRegistryPackages.new
      .publish("github.com/tunkshif/lsp", "lsp")
      .publish("github.com/elbywan/other", "other")
      .install

    response = BrowserClient.exec(Docs::Index.with(query: "tunkshif"))

    response.status_code.should eq(200)
    response.body.should contain("github.com/tunkshif/lsp")
    response.body.should_not contain("elbywan")
  end

  it "searches the registry by description" do
    StubRegistryPackages.new
      .publish(
        "github.com/kemalcr/kemal",
        "kemal",
        description: "HTTP web framework for Crystal"
      )
      .publish(
        "github.com/crystal-lang/postgres-driver",
        "postgres-driver",
        description: "Database abstraction layer"
      )
      .install

    response = BrowserClient.exec(Docs::Index.with(query: "HTTP"))

    response.status_code.should eq(200)
    response.body.should contain("kemal")
    response.body.should_not contain("postgres-driver")
  end

  it "reports the number of matches the registry found" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .install

    response = BrowserClient.exec(Docs::Index.with(query: "kemal"))

    response.status_code.should eq(200)
    response.body.should contain("Found 1 package")
  end

  # The total is the registry's, so pagination walks the whole catalogue and
  # not the handful of packages this app happens to hold rows for.
  it "paginates the registry's catalogue" do
    registry = StubRegistryPackages.new
    25.times { |index| registry.publish("github.com/owner/package-#{index}", "package-#{index}") }
    registry.install

    first = BrowserClient.exec(Docs::Index.with(page: 1))
    first.status_code.should eq(200)
    first.body.should contain("Page 1 of 2")

    second = BrowserClient.exec(Docs::Index.with(page: 2))
    second.status_code.should eq(200)
    second.body.should contain("Page 2 of 2")
  end

  it "does not repeat a package across pages" do
    registry = StubRegistryPackages.new
    25.times { |index| registry.publish("github.com/owner/package-#{index}", "package-#{index}") }
    registry.install

    first = BrowserClient.exec(Docs::Index.with(page: 1)).body
    second = BrowserClient.exec(Docs::Index.with(page: 2)).body

    # 25 shards over 20 per page: the second page holds the remaining five and
    # none of the first page's.
    repeated = (0...25).count do |index|
      slug = "github.com/owner/package-#{index}"
      first.includes?(slug) && second.includes?(slug)
    end

    repeated.should eq(0)
  end

  it "handles a search that matches nothing" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .install

    response = BrowserClient.exec(Docs::Index.with(query: "nonexistent"))

    response.status_code.should eq(200)
    response.body.should contain("No packages found")
  end

  it "shows an empty state when the registry holds nothing" do
    StubRegistryPackages.install

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should contain("No packages are indexed yet")
  end

  # An outage must not quietly turn back into the old behaviour. Listing this
  # app's own rows here would report a fraction of the ecosystem as all of it,
  # which is the exact bug, arriving on a timer instead of permanently.
  it "reports an outage rather than falling back to its own rows" do
    DocFactory.create &.package_name("locally-held")

    StubRegistryPackages.new(reachable: false).install

    response = BrowserClient.exec(Docs::Index)

    response.status_code.should eq(200)
    response.body.should contain("shard index is unavailable")
    response.body.should_not contain("locally-held")
  end

  it "lists alphabetically so pagination is stable" do
    StubRegistryPackages.new
      .publish("github.com/owner/zebra", "zebra")
      .publish("github.com/owner/alpha", "alpha")
      .install

    response = BrowserClient.exec(Docs::Index)

    alpha = response.body.index("github.com/owner/alpha")
    zebra = response.body.index("github.com/owner/zebra")

    alpha.should_not be_nil
    zebra.should_not be_nil
    alpha.not_nil!.should be < zebra.not_nil!
  end

  # Listing a package nobody has built is only half of it. The link on the
  # card has to reach the route that builds it, and the seam between the two
  # is `PackagePaths`: a host qualified key spelled as bare segments lands in
  # the legacy route and 404s. So the link is followed rather than assumed.
  describe "the link on an unbuilt package's card" do
    # The card leads with the shard's name, so that is what the anchor holds.
    href_on = ->(body : String, name : String) do
      match = body.match(/href="([^"]*)"[^>]*>#{Regex.escape(name)}</)
      match.try(&.[1])
    end

    it "lands on the page that builds it, not on a 404" do
      StubRegistryPackages.new
        .publish("github.com/kemalcr/kemal", "kemal", ["1.6.0"])
        .install
      StubDocsStorage.empty.install
      RecordingBuildQueue.install

      listing = BrowserClient.exec(Docs::Index)
      href = href_on.call(listing.body, "kemal")
      href.should eq("/docs/_/github.com/kemalcr/kemal")

      landed = BrowserClient.exec(Lucky::RouteHelper.new(:get, href.not_nil!))

      # The repository route redirects to the registry's current release,
      # which is where the build is commissioned.
      landed.status_code.should eq(302)

      built = BrowserClient.exec(
        Lucky::RouteHelper.new(:get, landed.headers["Location"])
      )
      built.status_code.should eq(200)
      built.body.should contain("Documentation is being built")
    end

    # A shard the registry has discovered but never cut a release for is
    # listable too, and gets the page that says so instead of a 404.
    it "explains a shard with no release rather than 404ing" do
      StubRegistryPackages.new
        .publish("github.com/owner/unreleased", "unreleased")
        .install

      listing = BrowserClient.exec(Docs::Index)
      href = href_on.call(listing.body, "unreleased")

      landed = BrowserClient.exec(Lucky::RouteHelper.new(:get, href.not_nil!))

      landed.status_code.should eq(200)
    end
  end

  # The badge has to name the version the link actually lands on. It used to
  # show `docs.current_version`, a copy of this fact taken when the package
  # was first registered, so a package whose registry release had moved on
  # advertised one version and served another.
  it "badges the version the card's link resolves to" do
    DocFactory.create &.package_name("github.com/kemalcr/kemal").current_version("1.5.0")

    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal", ["1.5.0", "1.6.0"])
      .install

    response = BrowserClient.exec(Docs::Index)

    response.body.should contain(%(<span class="doc-version">1.6.0</span>))
  end

  # The badge and the destination are computed by different code on different
  # sides of the boundary: the badge is `shards.latest_version`, written by
  # crystalshards, and the destination is this app's `default_release`. A
  # shard sitting on a release candidate is where they used to part company.
  it "badges and lands on the same version when a prerelease is newer" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal", ["1.9.0", "2.0.0-rc1"])
      .install
    StubDocsStorage.empty.install
    RecordingBuildQueue.install

    listing = BrowserClient.exec(Docs::Index)
    listing.body.should contain(%(<span class="doc-version">1.9.0</span>))

    landed = BrowserClient.exec(
      Lucky::RouteHelper.new(:get, "/docs/_/github.com/kemalcr/kemal")
    )

    landed.status_code.should eq(302)
    landed.headers["Location"].should eq("/docs/_/github.com/kemalcr/kemal/1.9.0")
  end

  # A negative page is a negative OFFSET, which Postgres rejects outright.
  it "clamps a page below the first" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .install

    response = BrowserClient.exec(Docs::Index.with(page: 0))

    response.status_code.should eq(200)
    response.body.should contain("github.com/kemalcr/kemal")
  end
end
