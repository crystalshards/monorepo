# A GitHub that answers a keyword code search, for driving ShardSearchProbe.
#
# Shared rather than kept in one spec file because two specs need it and they
# need it to be the same: the unit specs prove what the probe decides and sends,
# and the request specs prove that what it registered reaches the page. Both go
# through the real ShardSearchProbe, the real KeywordCrawler and the real
# Registrar over a real socket, so the only thing faked anywhere is the host.
#
# There is deliberately no seam over `ShardSearchProbe.request` itself. A second
# seam over the same call is how a spec ends up proving a path production does
# not take, and here it would skip the claim, the gating and the bound, which is
# most of what the module is.
module SearchProbeHost
  # Points the probe's crawler at `host` and gives the process a token, so
  # `enabled?` is true. Restores both afterwards whatever happens.
  def self.drive(host : FakeHost, &)
    previous_crawler = ShardSearchProbe.crawler
    previous_source = Discovery::Credentials.source

    Discovery::Credentials.source = {"GITHUB_TOKEN" => "probe-token"}
    ShardSearchProbe.crawler = ->(term : String) do
      Discovery::KeywordCrawler.new(
        term,
        base_url: host.base_url,
        token: "probe-token",
        # Backoff is asserted in the crawler's own specs. Here it would only
        # make a page load wait.
        sleeper: ->(_span : Time::Span) { },
      )
    end

    begin
      yield
    ensure
      ShardSearchProbe.crawler = previous_crawler
      Discovery::Credentials.source = previous_source
    end
  end

  # A host answering a code search with `items`, and a root shard.yml for exactly
  # the repositories in `manifests`.
  #
  # A match absent from `manifests` answers 404, which is how "code search said
  # so and there is no manifest there" is reproduced. That case is the reason the
  # crawler engine reads a candidate's shard.yml at all rather than trusting
  # `path:/`.
  def self.searchable(
    host : FakeHost,
    items : Array({String, String}),
    manifests : Hash(String, String) = {} of String => String,
    search_status : Int32 = 200,
  ) : FakeHost
    host.on(/\A\/search\/code/) do |_target, _count|
      FakeHost::Response.new(
        status: search_status,
        body: Discovery::Fixtures.github_code_search(items, total: items.size),
      )
    end

    host.on(/\A\/repos\/[^\/]+\/[^\/]+\/contents\/shard\.yml/) do |target, _count|
      match = target.match(%r{\A/repos/([^/]+)/([^/]+)/contents/shard\.yml}).not_nil!
      slug = "#{match[1]}/#{match[2]}"

      if manifest = manifests[slug]?
        FakeHost::Response.new(body: Discovery::Fixtures.github_contents(manifest))
      else
        FakeHost::Response.new(status: 404, body: %({"message":"Not Found"}))
      end
    end
  end

  def self.manifest(name : String) : String
    Discovery::Fixtures.shard_yml(name, "#{name} does a thing")
  end
end
