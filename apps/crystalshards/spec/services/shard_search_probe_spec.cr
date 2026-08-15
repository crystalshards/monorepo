require "../spec_helper"

# Taking a search the registry could not answer to GitHub, once.
#
# Driven over a real socket against FakeHost, like every other crawler spec
# here, and deliberately not against a stubbed crawler. The two things most
# worth proving are the query string this sends and the fact that it reads a
# shard.yml before believing a result, and a stubbed crawler proves neither.
private def with_probe(host : FakeHost, &)
  SearchProbeHost.drive(host) { yield }
end

private def searchable(
  host : FakeHost,
  items : Array({String, String}),
  manifests : Hash(String, String) = {} of String => String,
  search_status : Int32 = 200,
) : FakeHost
  SearchProbeHost.searchable(host, items, manifests, search_status)
end

private def manifest_for(name : String) : String
  SearchProbeHost.manifest(name)
end

private def probes : Array(SearchProbe)
  SearchProbeQuery.new.to_a
end

private def searched_query(host : FakeHost) : String
  target = host.requests.find { |request| request.includes?("/search/code") }.not_nil!
  URI::Params.parse(URI.parse(target.lchop("GET ")).query.not_nil!)["q"]
end

describe ShardSearchProbe do
  # The feature is for the search that failed. A query with a screenful of
  # results has been answered, and probing it would spend a shared
  # ten-a-minute bucket to append repositories nobody scrolled to want.
  it "does not probe a search the registry already answered" do
    FakeHost.run do |host|
      searchable(host, [] of {String, String})

      with_probe(host) do
        ShardSearchProbe.request("kemal", 40_i64).should be_nil
      end

      host.requests.should be_empty
    end

    probes.should be_empty
  end

  # Code search answers an unauthenticated request with 401, so a deployment
  # without a token cannot do this. Off, silently, and the process is fine: the
  # same arrangement the crawlers and mail already have here.
  it "is disabled without a credential" do
    previous = Discovery::Credentials.source
    Discovery::Credentials.source = {} of String => String

    begin
      ShardSearchProbe.enabled?.should be_false
      ShardSearchProbe.request("kemal", 0_i64).should be_nil
      probes.should be_empty
    ensure
      Discovery::Credentials.source = previous
    end
  end

  describe "the term" do
    it "ignores a term too short to mean anything" do
      FakeHost.run do |host|
        searchable(host, [] of {String, String})

        with_probe(host) { ShardSearchProbe.request("ab", 0_i64).should be_nil }

        host.requests.should be_empty
      end
    end

    it "ignores a term with nothing searchable in it" do
      FakeHost.run do |host|
        searchable(host, [] of {String, String})

        with_probe(host) { ShardSearchProbe.request("---", 0_i64).should be_nil }

        host.requests.should be_empty
      end
    end

    # Case and spacing are not part of what somebody meant, and three
    # formattings of one word must not each spend a request from a bucket that
    # allows ten a minute.
    it "treats differently formatted spellings of one term as one question" do
      FakeHost.run do |host|
        searchable(host, [{"kemalcr/kemal", "Web framework"}], {"kemalcr/kemal" => manifest_for("kemal")})

        with_probe(host) do
          ShardSearchProbe.request("Kemal", 0_i64).should eq(1)
          ShardSearchProbe.request("  kemal  ", 0_i64).should be_nil
          ShardSearchProbe.request("KEMAL", 0_i64).should be_nil
        end

        host.request_count(/search\/code/).should eq(1)
      end

      probes.map(&.term).should eq(["kemal"])
    end
  end

  describe "the query it sends" do
    # The term is added to the qualifier pair the exhaustive sweep uses rather
    # than replacing it, so a probe can only ever surface shards. Searching the
    # term alone would return applications, dotfiles and every README that
    # mentions the word.
    it "asks only for repositories with a shard.yml at their root" do
      FakeHost.run do |host|
        searchable(host, [] of {String, String})

        with_probe(host) { ShardSearchProbe.request("router", 0_i64) }

        searched_query(host).should eq("router filename:shard.yml path:/")
      end
    end

    # A search box is user input interpolated into a query language. The damage
    # a qualifier does here is not injection in the SQL sense, because there is
    # nothing to escape into: it is that `org:evil` silently changes which
    # repositories a probe registers, using our credential, on behalf of
    # whoever typed it.
    it "strips qualifier syntax out of what a visitor typed" do
      FakeHost.run do |host|
        searchable(host, [] of {String, String})

        with_probe(host) { ShardSearchProbe.request("router org:evil path:/etc", 0_i64) }

        searched_query(host).should eq("router org evil path etc filename:shard.yml path:/")
      end
    end
  end

  describe "what it registers" do
    it "registers a repository the registry had never seen, under its manifest's name" do
      FakeHost.run do |host|
        searchable(
          host,
          [{"kemalcr/kemal", "Fast, effective, simple web framework"}],
          {"kemalcr/kemal" => manifest_for("kemal")},
        )

        with_probe(host) { ShardSearchProbe.request("kemal", 0_i64).should eq(1) }
      end

      shard = ShardQuery.new.canonical_slug("github.com/kemalcr/kemal").first
      shard.name.should eq("kemal")
      shard.repository_url.should eq("https://github.com/kemalcr/kemal")
      # Registered, not indexed. A result card needs a name, a description and
      # a link; content costs three more requests each and nobody has opened
      # any of these pages yet. ShardIndexRequests indexes the one they click.
      shard.indexed_at.should be_nil
    end

    # `path:/` should guarantee a root shard.yml, but a qualifier we rely on and
    # a result we trust are not the same thing. The crawler engine reads the
    # manifest before believing a candidate, which is what keeps a probe from
    # filling the registry with whatever code search felt like matching.
    it "does not register a match whose shard.yml is not really there" do
      FakeHost.run do |host|
        searchable(
          host,
          [{"acme/not-a-shard", "An application"}, {"acme/real", "A library"}],
          {"acme/real" => manifest_for("real")},
        )

        with_probe(host) { ShardSearchProbe.request("thing", 0_i64).should eq(1) }
      end

      ShardQuery.new.canonical_slug("github.com/acme/not-a-shard").first?.should be_nil
      ShardQuery.new.canonical_slug("github.com/acme/real").first?.should_not be_nil
    end

    # The gap between the two is the number that says whether widening the
    # trigger would buy anything, so they are recorded separately.
    it "counts a repository it already had as known rather than new" do
      ShardFactory.create &.name("kemal").at("github.com", "kemalcr", "kemal")

      FakeHost.run do |host|
        searchable(host, [{"kemalcr/kemal", "Web framework"}], {"kemalcr/kemal" => manifest_for("kemal")})

        with_probe(host) { ShardSearchProbe.request("kemal", 0_i64).should eq(0) }
      end

      probe = probes.first
      probe.hits.should eq(1)
      probe.registered.should eq(0)
    end
  end

  describe "the claim" do
    # GitHub's code search allows ten requests a minute, on a bucket shared with
    # the exhaustive sweep, and the trigger is a text box. One crawler walking a
    # paginated listing would exhaust that minute and take the sweep with it.
    it "probes one term at most once inside the retry floor" do
      FakeHost.run do |host|
        searchable(host, [{"kemalcr/kemal", "Web framework"}], {"kemalcr/kemal" => manifest_for("kemal")})

        with_probe(host) do
          ShardSearchProbe.request("kemal", 0_i64).should eq(1)
          ShardSearchProbe.request("kemal", 0_i64).should be_nil
          ShardSearchProbe.request("kemal", 0_i64).should be_nil
        end

        host.request_count(/search\/code/).should eq(1)
      end

      probes.size.should eq(1)
    end

    it "probes again once the floor has passed" do
      FakeHost.run do |host|
        searchable(host, [{"kemalcr/kemal", "Web framework"}], {"kemalcr/kemal" => manifest_for("kemal")})

        with_probe(host) do
          ShardSearchProbe.request("kemal", 0_i64)

          AppDatabase.exec(
            "UPDATE search_probes SET probed_at = $1 WHERE term = $2",
            Time.utc - ShardSearchProbe::RETRY_FLOOR - 1.hour,
            "kemal",
          )

          ShardSearchProbe.request("kemal", 0_i64).should_not be_nil
        end

        host.request_count(/search\/code/).should eq(2)
      end

      # Re-probed, not duplicated: the claim is an upsert on the term.
      probes.size.should eq(1)
    end

    # Stamped before the search runs rather than after, so a probe whose process
    # died mid-flight still holds the claim and is retried on the ordinary
    # schedule instead of immediately by the next visitor.
    it "stamps the claim even when the search fails" do
      FakeHost.run do |host|
        searchable(host, [] of {String, String}, search_status: 500)

        with_probe(host) { ShardSearchProbe.request("kemal", 0_i64) }
      end

      probe = probes.first
      probe.term.should eq("kemal")
      probe.last_error.should_not be_nil
    end
  end

  describe "when it goes wrong" do
    # An empty result page is a worse answer than a full one and a much better
    # one than a 500.
    #
    # Zero rather than nil, and the difference is the contract: nil means no
    # probe happened, and a probe that reached the host and was refused did
    # happen. It registered nothing, it recorded why, and it holds its claim so
    # the next visitor does not walk into the same refusal.
    it "registers nothing and records why when the host refuses" do
      FakeHost.run do |host|
        searchable(host, [] of {String, String}, search_status: 500)

        with_probe(host) { ShardSearchProbe.request("kemal", 0_i64).should eq(0) }
      end

      probes.first.last_error.not_nil!.should contain("500")
    end

    it "answers nil rather than raising when the crawler itself blows up" do
      previous_crawler = ShardSearchProbe.crawler
      previous_source = Discovery::Credentials.source
      Discovery::Credentials.source = {"GITHUB_TOKEN" => "probe-token"}
      ShardSearchProbe.crawler = ->(_term : String) : Discovery::KeywordCrawler { raise "no socket for you" }

      begin
        ShardSearchProbe.request("kemal", 0_i64).should be_nil
      ensure
        ShardSearchProbe.crawler = previous_crawler
        Discovery::Credentials.source = previous_source
      end
    end
  end
end
