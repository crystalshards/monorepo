require "../../../spec_helper"

private def suggestion_names(response) : Array(String)
  JSON.parse(response.body)["suggestions"].as_a.map(&.["name"].as_s)
end

# The typeahead behind the masthead field.
#
# Its catalogue is the registry's, the same source the browse page reads, so
# these examples script the registry exactly as the browse ones do. What they
# pin down is what it refuses to do: ask on one character, return an unbounded
# list, or match in the middle of a name.
describe Api::Docs::Suggestions do
  it "offers nothing until the term reaches the minimum length" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .install

    response = ApiClient.exec(Api::Docs::Suggestions.with(query: "k"))

    response.status.should eq(HTTP::Status.new(200))
    suggestion_names(response).should be_empty
  end

  it "offers matches once it does" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .publish("github.com/amberframework/granite", "granite")
      .install

    response = ApiClient.exec(Api::Docs::Suggestions.with(query: "ke"))

    suggestion_names(response).should eq(["kemal"])
  end

  it "matches the repository slug, so an owner's packages are reachable by typing the host" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .publish("gitlab.com/amberframework/granite", "granite")
      .install

    response = ApiClient.exec(Api::Docs::Suggestions.with(query: "gitlab.com/amber"))

    suggestion_names(response).should eq(["granite"])
  end

  # Prefixes, not substrings. The search page behind the Enter key still
  # matches anywhere in the name, the slug or the description; this one is
  # guessing at a name the reader is part way through spelling, and it is the
  # only shape a btree index can serve.
  it "matches the start of a name rather than anywhere in it" do
    StubRegistryPackages.new
      .publish("github.com/someone/crystal-kemal", "crystal-kemal")
      .install

    response = ApiClient.exec(Api::Docs::Suggestions.with(query: "kemal"))

    suggestion_names(response).should be_empty
  end

  it "returns at most eight, however many match" do
    registry = StubRegistryPackages.new
    12.times do |index|
      registry.publish("github.com/kemalcr/kemal-plugin-#{index}", "kemal-plugin-#{index}")
    end
    registry.install

    response = ApiClient.exec(Api::Docs::Suggestions.with(query: "kemal"))

    suggestion_names(response).size.should eq(CrystalDocs::PackageSuggestions::LIMIT)
  end

  # The canonical route, which is where this package's browse card links and
  # which registers the package and commissions a build on first visit. The
  # suggestion must not invent a second address for a package the catalogue
  # already knows how to address.
  it "carries the package's path and repository" do
    StubRegistryPackages.new
      .publish("github.com/kemalcr/kemal", "kemal")
      .install

    response = ApiClient.exec(Api::Docs::Suggestions.with(query: "kemal"))

    suggestion = JSON.parse(response.body)["suggestions"].as_a.first
    suggestion["path"].should eq("/docs/_/github.com/kemalcr/kemal")
    suggestion["repository"].should eq("github.com/kemalcr/kemal")
  end

  # Deliberately unlike `Api::Docs::Index`, which answers 503 rather than an
  # empty catalogue because an empty list there is a claim that no such shard
  # exists and a client would cache it. Nothing caches this, nothing reads
  # absence from it, and the reader still has a search form that submits.
  it "offers nothing, rather than an outage, when the registry cannot be reached" do
    StubRegistryPackages.new(reachable: false).install

    response = ApiClient.exec(Api::Docs::Suggestions.with(query: "kemal"))

    response.status.should eq(HTTP::Status.new(200))
    suggestion_names(response).should be_empty
  end
end
