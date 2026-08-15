require "../../spec_helper"

# A search the registry cannot answer, answered by going and looking.
#
# The service specs cover what ShardSearchProbe decides and what it sends. These
# cover the only thing a visitor experiences: whether the shard it found is on
# the page they are looking at. That is a separate question, because the count
# and the page are both read from the database before the probe writes anything,
# and a page rendered from those would say "no shards found" over rows that now
# exist.
#
# Driven through the real probe, the real crawler and the real registrar against
# FakeHost, so the claim, the gating and the bound are all in the path.
describe "expanding a search to GitHub" do
  # The one that matters. Everything the action does after the probe exists so
  # that this passes: re-count, then re-query, then render.
  it "renders a shard the probe registered during this request" do
    ShardQuery.new.canonical_slug("github.com/lpm11/crystal-mecab").first?.should be_nil

    FakeHost.run do |host|
      SearchProbeHost.searchable(
        host,
        [{"lpm11/crystal-mecab", "MeCab bindings"}],
        {"lpm11/crystal-mecab" => SearchProbeHost.manifest("mecab")},
      )

      SearchProbeHost.drive(host) do
        response = BrowserClient.exec(Shards::Index.with(query: "mecab"))

        response.status_code.should eq(200)
        response.body.should contain("mecab")
      end
    end

    # Registered, and registered as a real row rather than as page text.
    shard = ShardQuery.new.canonical_slug("github.com/lpm11/crystal-mecab").first
    shard.name.should eq("mecab")
  end

  # A page built before the probe reports the old count beside the new rows,
  # which is the same silently-wrong-number failure the dependent counts were
  # fixed for. The count is read again only when the probe actually registered
  # something, so this is the assertion that the "again" happens at all.
  it "counts what the probe found rather than what the search started with" do
    FakeHost.run do |host|
      SearchProbeHost.searchable(
        host,
        [{"lpm11/crystal-mecab", "MeCab bindings"}],
        {"lpm11/crystal-mecab" => SearchProbeHost.manifest("mecab")},
      )

      SearchProbeHost.drive(host) do
        response = BrowserClient.exec(Shards::Index.with(query: "mecab"))

        # The listing prints "Found N shard(s) matching". Before the re-count it
        # printed "Found 0 shards" while rendering the row the probe had just
        # written directly underneath.
        response.body.should contain("Found 1 shard matching")
      end
    end
  end

  it "renders normally when the probe finds nothing" do
    FakeHost.run do |host|
      SearchProbeHost.searchable(host, [] of {String, String})

      SearchProbeHost.drive(host) do
        response = BrowserClient.exec(Shards::Index.with(query: "nothing-like-this-exists"))

        response.status_code.should eq(200)
      end
    end
  end

  # The ordinary case, and the one that must be exactly what it was before any
  # of this existed: no credential, so no probe, and a page rendered from the
  # database alone.
  it "renders normally with no credential and probes nothing" do
    previous = Discovery::Credentials.source
    Discovery::Credentials.source = {} of String => String
    ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

    begin
      response = BrowserClient.exec(Shards::Index.with(query: "kemal"))

      response.status_code.should eq(200)
      response.body.should contain("kemal")
      SearchProbeQuery.new.select_count.should eq(0)
    ensure
      Discovery::Credentials.source = previous
    end
  end

  # The action supplies the local count that gates the probe, so a search the
  # registry answered must not spend a request. Asserted here as well as in the
  # service specs because supplying the wrong number is an action-level mistake
  # that would probe on every search.
  it "does not probe a search the registry already answered" do
    4.times do |index|
      ShardFactory.create &.name("router-#{index}").at("github.com", "acme", "router-#{index}")
    end

    FakeHost.run do |host|
      SearchProbeHost.searchable(host, [] of {String, String})

      SearchProbeHost.drive(host) do
        response = BrowserClient.exec(Shards::Index.with(query: "router"))

        response.status_code.should eq(200)
      end

      host.requests.should be_empty
    end

    SearchProbeQuery.new.select_count.should eq(0)
  end
end
