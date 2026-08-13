require "../../../spec_helper"

# The JSON catalogue, from the registry for the same reason the HTML one is.
# This is the endpoint a client resolves a package name against, and answering
# it from the `docs` table meant a name only resolved after somebody had
# already opened that package on the website.
describe Api::Docs::Index do
  it "returns an empty list when the registry holds nothing" do
    StubRegistryPackages.install

    response = ApiClient.exec(Api::Docs::Index)

    response.should send_json(200, {docs: [] of String, meta: {page: 1, per_page: 20, total: 0}})
  end

  it "returns the registry's packages" do
    StubRegistryPackages.new
      .publish(
        "github.com/kemalcr/kemal",
        "kemal",
        ["1.6.0"],
        description: "A test package documentation"
      )
      .install

    response = ApiClient.exec(Api::Docs::Index)

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("github.com/kemalcr/kemal")
    response.body.should contain("A test package documentation")
  end

  # A package with no local row is still a package. It reports the registry's
  # latest version and nulls for everything only a build could fill in.
  it "returns a registry package this app has never built" do
    StubRegistryPackages.new
      .publish("github.com/tunkshif/lsp", "lsp", ["0.1.0"])
      .install

    response = ApiClient.exec(Api::Docs::Index)

    json = JSON.parse(response.body)
    entry = json["docs"].as_a.first

    entry["package_name"].should eq("github.com/tunkshif/lsp")
    entry["current_version"].should eq("0.1.0")
    entry["last_updated_at"].as_s?.should be_nil
  end

  # The registry's current release, not the copy of it this app took when the
  # package was first registered. `docs.current_version` is written once by
  # `PackageRegistration` and never refreshed, so a package whose release has
  # moved on would otherwise report a version the site no longer sends
  # readers to.
  it "reports the registry's current release over its own stale copy" do
    DocFactory.create &.package_name("github.com/kemalcr/kemal").current_version("1.5.0")

    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal", ["1.5.0", "1.6.0"])
      .install

    response = ApiClient.exec(Api::Docs::Index)

    json = JSON.parse(response.body)
    json["docs"].as_a.first["current_version"].should eq("1.6.0")
  end

  it "paginates over the registry's total" do
    registry = StubRegistryPackages.new
    25.times { |index| registry.publish("github.com/owner/package-#{index}", "package-#{index}") }
    registry.install

    response = ApiClient.exec(Api::Docs::Index.with(page: 2, per_page: 10))

    response.status.should eq(HTTP::Status.new(200))
    json = JSON.parse(response.body)
    json["docs"].as_a.size.should eq(10)
    json["meta"]["page"].should eq(2)
    json["meta"]["total"].should eq(25)
  end

  it "searches the registry by name" do
    StubRegistryPackages.new
      .publish("github.com/owner/awesome-lib", "awesome-lib")
      .publish("github.com/owner/cool-tool", "cool-tool")
      .install

    response = ApiClient.exec(Api::Docs::Index.with(query: "awesome"))

    response.status.should eq(HTTP::Status.new(200))
    response.body.should contain("awesome-lib")
    response.body.should_not contain("cool-tool")
  end

  # An empty array would tell a client the registry has no such shard, and a
  # client cannot tell that apart from an outage. It would cache the absence.
  it "reports an outage rather than an empty catalogue" do
    DocFactory.create &.package_name("locally-held")

    StubRegistryPackages.new(reachable: false).install

    response = ApiClient.exec(Api::Docs::Index)

    response.status.should eq(HTTP::Status.new(503))
    response.body.should_not contain("locally-held")
  end
end
