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

describe Discovery::BitbucketCrawler do
  describe "walking the registered workspaces" do
    it "follows pagination past the first page and stops when the host stops offering one" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/router", "a router"}],
              next_page: "https://api.bitbucket.org/2.0/repositories/acme?pagelen=100&page=2",
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
        # Page two was actually asked for, and asked for by page number rather
        # than by following the absolute URL the host handed back.
        fake.requests.select(&.includes?("/repositories/acme?")).size.should eq(2)
        fake.requests.any?(&.includes?("page=2")).should be_true
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

    it "publishes a cursor naming the workspace and the page after every page" do
      FakeHost.run do |fake|
        serve_workspaces(fake, {
          "acme" => [
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories(
              [{"acme/router", ""}], next_page: "https://api.bitbucket.org/2.0/repositories/acme?page=2")),
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

        cursors.should eq(["acme:2", "beta:1", nil])
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
        report.cursor.should eq("beta:1")
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
        report.cursor.should eq("beta:1")
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

    it "keeps the host's absolute next URL out of the cursor entirely" do
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

        cursors = [] of String?
        crawler = bitbucket(fake, ["acme"])
        crawler.on_page = ->(cursor : String?) { cursors << cursor; nil }
        crawler.run

        # `next` was read as a yes-or-no and its value discarded, so the next
        # page was asked for by number against the configured base.
        cursors.should eq(["acme:2", nil])
        fake.requests.none?(&.includes?("evil.test")).should be_true
      end
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
