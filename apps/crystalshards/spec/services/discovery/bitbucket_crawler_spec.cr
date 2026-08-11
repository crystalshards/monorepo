require "../../spec_helper"

# Bitbucket is the one host in the registry with no global enumeration behind
# it, so these specs defend two different things: that the workspace walk has
# the same durability guarantees as every other host's sweep, and that it never
# reports the workspaces it was given as if they were the host.
#
# Every fixture here is a recording. Provenance is stated on each one in
# spec/support/discovery/fixtures.cr, including the one place where the
# transport is real and the file content is invented, because there is no public
# Crystal shard on Bitbucket to record a real shard.yml from.
# The one fixture whose bytes are invented rather than recorded, wrapped so every
# use of it is findable by name. The 200 and the text/plain around these bytes
# are exactly what Bitbucket's raw file endpoint was observed to send.
private def shard_response(name : String) : FakeHost::Response
  body, headers = Discovery::Fixtures.bitbucket_shard_yml_response(name)
  FakeHost::Response.new(body: body, headers: headers)
end

private def bitbucket(
  fake : FakeHost,
  workspaces : Array(String),
  sleeper : RecordedSleeper? = nil,
  max_pages : Int32? = nil,
) : Discovery::BitbucketCrawler
  Discovery::BitbucketCrawler.new(
    workspaces: workspaces,
    base_url: fake.base_url,
    token: "spec-app-password",
    username: "spec-account",
    sleeper: sleeper.try(&.to_proc),
    max_pages: max_pages,
  )
end

# The enumeration route, answering with whichever workspace was asked for.
private def serve_workspaces(fake : FakeHost, pages : Hash(String, Array(FakeHost::Response)))
  seen = Hash(String, Int32).new(0)

  fake.on(/\/repositories\/[^\/?]+\?/) do |target, _attempt|
    slug = target.match(/\/repositories\/([^\/?]+)\?/).try(&.[1]) || ""
    index = seen[slug]
    seen[slug] = index + 1
    responses = pages[slug]? || [] of FakeHost::Response
    responses[index]? || responses.last? || FakeHost::Response.new(status: 404, body: "{}")
  end
end

# A cursor is JSON carrying the host's own next URL, so specs about where a
# sweep is compare the parsed position rather than the spelling of it.
private def position_of(cursor : String?) : String?
  return nil unless cursor

  position = Discovery::BitbucketCrawler::Position.parse(cursor).not_nil!
  "#{position.slug}:#{position.page}"
end

# What the cursor will make the crawler ask for next, which is the host's URL
# once there is one to follow.
private def follow_of(cursor : String?) : String?
  return nil unless cursor

  Discovery::BitbucketCrawler::Position.parse(cursor).not_nil!.follow
end

describe Discovery::BitbucketCrawler do
  describe "walking the registered workspaces" do
    it "follows the host's own next link past the first page and stops when it stops offering one" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/router", "a router"}],
              next_page: "#{fake.base_url}/repositories/acme?pagelen=100&page=2",
              size: 2, page: 1,
            )),
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/logger", "a logger"}],
              size: 2, page: 2,
            )),
          ],
        })
        fake.on(/\/src\/master\/shard\.yml/) do |target, _|
          name = target.includes?("router") ? "router" : "logger"
          shard_response(name)
        end

        report = bitbucket(fake, ["acme"]).run

        report.pages.should eq(2)
        report.discovered.should eq(2)
        # Page two was actually asked for, and asked for by following the link
        # the host gave rather than by a URL rebuilt from a page counter.
        fake.requests.select(&.includes?("/repositories/acme?")).size.should eq(2)
        fake.requests.any?(&.includes?("page=2")).should be_true
      end
    end

    # The reason the link is followed rather than reconstructed. A Bitbucket
    # paginated body only guarantees `values` and `next`; this one is in that
    # minimum shape, with no `page` field at all and a `next` whose query is an
    # opaque token. Nothing here can be rebuilt from a counter, so a crawler
    # that synthesised page+1 would ask for a page the host never offered and
    # silently lose everything after page one.
    it "follows an opaque next link on a body carrying no page number" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/router", "a router"}],
              next_page: "#{fake.base_url}/repositories/acme?ctx=b7e1f0a9d4&pagelen=100",
              size: 2, page: nil,
            )),
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/logger", "a logger"}],
              size: 2, page: nil,
            )),
          ],
        })
        fake.on(/\/src\/master\/shard\.yml/) do |target, _|
          name = target.includes?("router") ? "router" : "logger"
          shard_response(name)
        end

        report = bitbucket(fake, ["acme"]).run

        report.pages.should eq(2)
        report.discovered.should eq(2)
        # Not asserting complete? here: this host is never complete, whatever
        # the pagination did. That guarantee has its own spec below.
        # The opaque token was carried through verbatim.
        fake.requests.any?(&.includes?("ctx=b7e1f0a9d4")).should be_true
      end
    end

    it "walks to the next workspace when one runs out of pages" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme"  => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/router", ""}]))],
          "beta"  => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"beta/parser", ""}]))],
          "gamma" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"gamma/http", ""}]))],
        })
        fake.on(/\/src\/master\/shard\.yml/) do |target, _|
          shard_response(target.split('/')[3])
        end

        report = bitbucket(fake, ["gamma", "acme", "beta"]).run

        report.discovered.should eq(3)
        # Sorted, so the cursor's slug always names the same place in the walk.
        enumerated = fake.requests.select(&.includes?("/repositories/")).compact_map do |request|
          request.match(/\/repositories\/([^\/?]+)\?/).try(&.[1])
        end
        enumerated.should eq(["acme", "beta", "gamma"])
      end
    end

    it "publishes a cursor naming the workspace, the page, and the link to resume with" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/router", ""}], next_page: "#{fake.base_url}/repositories/acme?page=2")),
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/logger", ""}])),
          ],
          "beta" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"beta/parser", ""}]))],
        })
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("anything")
        end

        cursors = [] of String?
        crawler = bitbucket(fake, ["acme", "beta"])
        crawler.on_page = ->(cursor : String?) { cursors << cursor; nil }
        crawler.run

        cursors.map { |cursor| position_of(cursor) }.should eq(["acme:2", "beta:1", nil])
        # Mid-workspace the cursor carries the host's link, so a resumed sweep
        # asks for the page the host named rather than one it worked out.
        follow_of(cursors.first).should eq("#{fake.base_url}/repositories/acme?page=2")
        # Crossing into a new workspace there is no link yet, so the first page
        # of it is built here.
        follow_of(cursors[1]).should be_nil
      end
    end

    it "resumes from a persisted cursor instead of starting the walk over" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "beta" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"beta/parser", ""}]))],
        })
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("parser")
        end

        bitbucket(fake, ["acme", "beta"]).run("beta:1")

        enumerated = fake.requests.select(&.includes?("/repositories/")).compact_map do |request|
          request.match(/\/repositories\/([^\/?]+)\?/).try(&.[1])
        end
        # acme comes first in the list and was not asked for again.
        enumerated.should eq(["beta"])
      end
    end

    it "resumes mid-workspace at the page the cursor names" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/logger", ""}], page: 3))],
        })
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("logger")
        end

        bitbucket(fake, ["acme"]).run("acme:3")

        fake.requests.find(&.includes?("/repositories/acme")).not_nil!.should contain("page=3")
      end
    end

    it "picks up at the next workspace when the one the cursor named is no longer registered" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "gamma" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"gamma/http", ""}]))],
        })
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("http")
        end

        # The cursor stopped in "beta", which has since been unregistered. The
        # workspaces before it must not be redone and the ones after it must not
        # be skipped.
        bitbucket(fake, ["acme", "gamma"]).run("beta:2")

        enumerated = fake.requests.select(&.includes?("/repositories/")).compact_map do |request|
          request.match(/\/repositories\/([^\/?]+)\?/).try(&.[1])
        end
        enumerated.should eq(["gamma"])
      end
    end
  end

  describe "the rate limit" do
    it "waits the seconds the host asked for, not a timestamp's worth, then retries" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new

        fake.on(/\/repositories\/acme\?/) do |_target, attempt|
          if attempt.zero?
            # Verbatim live header shape: reset is seconds remaining, not epoch.
            FakeHost::Response.new(
              status: 429,
              body: %({"type":"error","error":{"message":"Rate limit for this resource has been exceeded"}}),
              headers: Discovery::Fixtures.bitbucket_rate_limit_headers(45),
            )
          else
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/router", ""}]))
          end
        end
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("router")
        end

        report = bitbucket(fake, ["acme"], sleeper: sleeper).run

        # 45 means 45 seconds. Read as a Unix timestamp it is 1970, the
        # subtraction goes negative, and the floor turns the pause into one
        # second: the crawl would spend its retries in five seconds flat.
        sleeper.waits.should eq([45.seconds])
        report.discovered.should eq(1)
        report.status.should eq(CrawlState::Status::PARTIAL)
      end
    end

    it "stops with the cursor intact rather than reporting a short crawl as finished" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new

        fake.on(/\/repositories\/acme\?/) do
          FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/router", ""}]))
        end
        fake.on(/\/repositories\/beta\?/) do
          FakeHost::Response.new(
            status: 429,
            body: "{}",
            # Longer than the crawl will hold, so it stops instead of sleeping.
            headers: Discovery::Fixtures.bitbucket_rate_limit_headers(3_600),
          )
        end
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("router")
        end

        report = bitbucket(fake, ["acme", "beta"], sleeper: sleeper).run

        report.status.should eq(CrawlState::Status::PARTIAL)
        report.stop_reason.should eq(CrawlState::StopReason::RATE_LIMITED)
        # The cursor still points at the workspace that was not read.
        position_of(report.cursor).should eq("beta:1")
        report.complete?.should be_false
      end
    end
  end

  describe "a workspace that will not answer" do
    it "steps over a 403 so the workspaces after it are still crawled" do
      FakeHost.run do |fake|
        problems = [] of {String, String}

        fake.on(/\/repositories\/acme\?/) do
          FakeHost::Response.new(status: 403, body: %({"type":"error","error":{"message":"Access denied"}}))
        end
        fake.on(/\/repositories\/beta\?/) do
          FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"beta/parser", ""}]))
        end
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("parser")
        end

        crawler = bitbucket(fake, ["acme", "beta"])
        crawler.on_workspace_problem = ->(slug : String, reason : String) { problems << {slug, reason}; nil }
        report = crawler.run

        # Stopping at acme would mean beta is never reached, on this run or any
        # other, because the cursor would never get past it.
        report.discovered.should eq(1)
        report.failed.should eq(1)
        problems.map(&.[0]).should eq(["acme"])
        report.complete?.should be_false
      end
    end

    it "holds the cursor on a workspace the host failed to serve, so it is retried" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new

        fake.on(/\/repositories\/acme\?/) do
          FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/router", ""}]))
        end
        # A 500 is the host having a bad minute, not this workspace refusing.
        # Advancing past it would drop the workspace from the crawl until
        # somebody ran a fresh sweep.
        fake.on(/\/repositories\/beta\?/) do
          FakeHost::Response.new(status: 500, body: "upstream error")
        end
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("router")
        end

        report = bitbucket(fake, ["acme", "beta"], sleeper: sleeper).run

        report.status.should eq(CrawlState::Status::FAILED)
        position_of(report.cursor).should eq("beta:1")
      end
    end

    it "does not turn one bad credential into a list of individually broken workspaces" do
      FakeHost.run do |fake|
        fake.on(/\/repositories\/[^\/?]+\?/) do
          FakeHost::Response.new(status: 401, body: %({"type":"error","error":{"message":"Invalid credentials"}}))
        end

        report = bitbucket(fake, ["acme", "beta", "gamma"]).run

        # A 401 is the whole host refusing the credential. Skipping every
        # workspace one at a time would file one fixable problem as three.
        report.status.should eq(CrawlState::Status::FAILED)
        report.failed.should eq(0)
        fake.requests.select(&.includes?("/repositories/")).size.should eq(1)
      end
    end
  end

  describe "deciding what is a shard" do
    it "skips a repository with no shard.yml at its root instead of storing it" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
            [{"acme/router", "a router"}, {"acme/website", "not a shard"}]
          ))],
        })
        fake.on(/\/repositories\/acme\/router\/src\/master\/shard\.yml/) do
          shard_response("router")
        end
        fake.on(/\/repositories\/acme\/website\/src\/master\/shard\.yml/) do
          FakeHost::Response.new(status: 404, body: Discovery::Fixtures::BITBUCKET_FILE_MISSING)
        end

        report = bitbucket(fake, ["acme"]).run

        report.discovered.should eq(1)
        report.skipped.should eq(1)
        ShardQuery.new.canonical_slug("bitbucket.org/acme/website").first?.should be_nil
        ShardQuery.new.canonical_slug("bitbucket.org/acme/router").first?.should_not be_nil
      end
    end

    it "resolves the main branch from the enumeration instead of guessing master or main" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
            [{"acme/router", ""}], main_branch: "trunk"
          ))],
        })
        fake.on(/\/src\/trunk\/shard\.yml/) do
          shard_response("router")
        end
        # Guessing would land here, and Bitbucket answers a bad ref with the
        # same 404 as a missing file, so the shard would be filed as not a shard.
        fake.on(/\/src\/(master|main)\/shard\.yml/) do
          FakeHost::Response.new(status: 404, body: Discovery::Fixtures::BITBUCKET_REF_MISSING)
        end

        report = bitbucket(fake, ["acme"]).run

        report.discovered.should eq(1)
        fake.requests.any?(&.includes?("/src/trunk/shard.yml")).should be_true
      end
    end

    it "spends no request on a repository with no main branch, because it has no commits" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
            [{"acme/empty", ""}], main_branch: nil
          ))],
        })

        report = bitbucket(fake, ["acme"]).run

        report.skipped.should eq(1)
        report.discovered.should eq(0)
        fake.requests.any?(&.includes?("shard.yml")).should be_false
      end
    end

    it "does not treat a transport failure as an answer about whether a repository is a shard" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/router", ""}]))],
        })
        fake.on(/\/src\/master\/shard\.yml/) do
          FakeHost::Response.new(status: 500, body: "gateway blew up")
        end

        report = bitbucket(fake, ["acme"]).run

        # Counting this as "not a shard" is how a bad minute on the host quietly
        # empties a workspace out of the registry.
        report.status.should eq(CrawlState::Status::FAILED)
        report.skipped.should eq(0)
        report.discovered.should eq(0)
      end
    end

    it "skips a Mercurial repository rather than storing one a git provider cannot clone" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
            [{"acme/ancient", ""}], scm: "hg"
          ))],
        })

        report = bitbucket(fake, ["acme"]).run

        report.skipped.should eq(1)
        report.discovered.should eq(0)
      end
    end
  end

  describe "seeing the same repository twice" do
    it "updates the row it already has instead of adding another" do
      FakeHost.run do |fake|
        fake.on(/\/repositories\/acme\?/) do |_target, attempt|
          description = attempt.zero? ? "first sighting" : "second sighting"
          FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/router", description}]))
        end
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("router")
        end

        first = bitbucket(fake, ["acme"]).run
        second = bitbucket(fake, ["acme"]).run

        first.discovered.should eq(1)
        # The identity is the key, so the second sighting is an update.
        second.discovered.should eq(0)
        second.updated.should eq(1)
        ShardQuery.new.canonical_slug("bitbucket.org/acme/router").select_count.should eq(1)
      end
    end
  end

  describe "what the crawl will talk to" do
    it "refuses a URL that is not the endpoint it was configured with" do
      FakeHost.run do |fake|
        crawler = bitbucket(fake, ["acme"])
        gate = crawler.url_gate_for(fake.base_url).not_nil!

        # The shape of Bitbucket's own `next`: an absolute URL in the response
        # body. If a response could nominate the next request's host, the host's
        # JSON would be an SSRF primitive.
        expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /may only reach/) do
          gate.call("https://api.bitbucket.org/2.0/repositories/acme?page=2")
        end
        expect_raises(Discovery::ApiEndpointPolicy::BlockedError, /may only reach/) do
          gate.call("http://169.254.169.254/latest/meta-data/")
        end

        # The endpoint it was configured with is still fine.
        gate.call("#{fake.base_url}/repositories/acme?page=1")
      end
    end

    # Following a link out of a response body is the thing that needs guarding,
    # so the guard is checked where it matters: before the link is written to a
    # cursor, because a cursor is persisted and would otherwise carry a bad
    # destination into every later run.
    it "refuses a next link that leaves the configured origin, and never persists it" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/router", ""}],
              next_page: "https://evil.test/2.0/repositories/acme?page=2",
            )),
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/logger", ""}])),
          ],
        })
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("anything")
        end

        problems = [] of {String, String}
        cursors = [] of String?
        crawler = bitbucket(fake, ["acme"])
        crawler.on_workspace_problem = ->(slug : String, reason : String) { problems << {slug, reason}; nil }
        crawler.on_page = ->(cursor : String?) { cursors << cursor; nil }
        report = crawler.run

        fake.requests.none?(&.includes?("evil.test")).should be_true
        cursors.compact_map { |cursor| follow_of(cursor) }.should be_empty
        # Recorded as a broken workspace rather than quietly treated as the end
        # of the pages, which would report a truncated read as a finished one.
        problems.map(&.[0]).should eq(["acme"])
        problems.first[1].should contain("evil.test")
        report.complete?.should be_false
      end
    end

    # Same origin, different resource. Without this a workspace could hand the
    # sweep off to another workspace's collection and have whatever came back
    # counted under its own coverage.
    it "refuses a next link that leaves this workspace's own collection" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/router", ""}],
              next_page: "#{fake.base_url}/repositories/other-workspace?page=2",
            )),
          ],
        })
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("anything")
        end

        problems = [] of {String, String}
        crawler = bitbucket(fake, ["acme"])
        crawler.on_workspace_problem = ->(slug : String, reason : String) { problems << {slug, reason}; nil }
        crawler.run

        fake.requests.none?(&.includes?("other-workspace")).should be_true
        problems.map(&.[0]).should eq(["acme"])
      end
    end

    # A cursor written by the version of this crawler that stored "<slug>:<page>"
    # is sitting in a database mid-sweep. It still has to mean what it meant.
    it "still understands a cursor written before links were followed" do
      legacy = Discovery::BitbucketCrawler::Position.parse("acme:4").not_nil!

      legacy.slug.should eq("acme")
      legacy.page.should eq(4)
      # Nothing to follow, so the page is built from the counter, which is
      # exactly the old behaviour and is correct for one request.
      legacy.follow.should be_nil
    end
  end

  describe "what a finished sweep claims" do
    it "records a completed walk as workspace scoped, never as a complete view of the host" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/router", ""}]))],
        })
        fake.on(/\/src\/master\/shard\.yml/) do
          shard_response("router")
        end

        report = bitbucket(fake, ["acme"]).run

        report.status.should eq(CrawlState::Status::PARTIAL)
        report.stop_reason.should eq(CrawlState::StopReason::COMPLETED_WORKSPACE_SCOPED)
        report.complete?.should be_false
      end
    end

    it "says it looked nowhere when no workspace is registered, rather than finding nothing" do
      FakeHost.run do |fake|
        report = bitbucket(fake, [] of String).run

        report.stop_reason.should eq(CrawlState::StopReason::NO_WORKSPACES_REGISTERED)
        report.discovered.should eq(0)
        # Zero shards because zero places were looked, and the row says which.
        fake.requests.should be_empty
      end
    end
  end
end
