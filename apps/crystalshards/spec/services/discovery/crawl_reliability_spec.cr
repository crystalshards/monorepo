require "../../spec_helper"

# Reliability is the requirement, not a nice-to-have, because a crawl that stops
# halfway leaves the registry looking complete when it is not. Each example here
# is one of the ways that happens.
#
# Every response is a recorded fixture served over a real socket by FakeHost, so
# the crawler's own HTTP path, header handling and pagination run unmodified. No
# example talks to a real host.

private def github_crawler(host : FakeHost, sleeper : RecordedSleeper? = nil, max_pages : Int32? = nil)
  Discovery::GithubCrawler.new(
    base_url: host.base_url,
    token: "spec-token",
    sleeper: sleeper.try(&.to_proc),
    max_pages: max_pages,
  )
end

private def shard_yml_route(host : FakeHost, name : String = "example")
  host.on(/\/contents\/shard\.yml/) do
    FakeHost::Response.new(body: Discovery::Fixtures.github_contents(Discovery::Fixtures.shard_yml(name)))
  end
end

# The page number the crawler asked for.
private def requested_page(target : String) : Int32
  URI.parse(target).query_params["page"]?.try(&.to_i) || 1
end

# True when the request is for the crawler's first size window. GitHub
# enumeration always has a second, open-ended window behind it, and a fake that
# answers every window with the same items would serve the same repositories
# twice and make a correct crawl look like it double counted.
private def first_window?(target : String) : Bool
  target.includes?("size%3A0..") || target.includes?("size:0..")
end

# Serves `items` for the crawler's first size window and nothing for the rest,
# which is how a real host behaves: a repository's shard.yml has one size and so
# appears in exactly one window.
private def single_window_search(host : FakeHost, items : Array({String, String}))
  host.on(/\/search\/code/) do |target|
    if first_window?(target)
      FakeHost::Response.new(body: Discovery::Fixtures.github_code_search(items, total: items.size))
    else
      FakeHost::Response.new(body: Discovery::Fixtures.github_code_search([] of {String, String}, total: 0))
    end
  end
end

describe "discovery reliability" do
  describe "pagination" do
    it "continues past the first page instead of stopping at it" do
      FakeHost.run do |fake|
        # 150 matches in the first size window: two pages of 100, and a crawl
        # that reads only the first would miss a third of the host and report
        # itself done.
        fake.on(/\/search\/code/) do |target|
          unless first_window?(target)
            next FakeHost::Response.new(body: Discovery::Fixtures.github_code_search([] of {String, String}, total: 0))
          end

          items = if requested_page(target) == 1
                    Array.new(100) { |i| {"owner#{i}/repo#{i}", "first page"} }
                  else
                    Array.new(50) { |i| {"owner1#{i}/repo1#{i}", "second page"} }
                  end
          FakeHost::Response.new(body: Discovery::Fixtures.github_code_search(items, total: 150))
        end
        shard_yml_route(fake)

        report = github_crawler(fake).run

        report.pages.should be >= 2
        fake.request_count(/page=2/).should eq(1)
        (report.discovered + report.updated).should eq(150)
        report.status.should eq(CrawlState::Status::COMPLETED)
      end
    end

    it "splits a search window that matched more results than the host will return" do
      FakeHost.run do |fake|
        # GitHub caps any search at 1000 results however many matched. A window
        # reporting more than that has to be divided, or everything past the cap
        # is invisible while the crawl looks successful.
        #
        # Only the full 0..4096 window is oversized here. Its halves answer
        # normally, so the sweep splits once and then proceeds, which is what
        # lets this example assert both halves were actually visited.
        fake.on(/\/search\/code/) do |target|
          total = target.includes?("size%3A0..4096") ? 4000 : 0
          FakeHost::Response.new(body: Discovery::Fixtures.github_code_search([] of {String, String}, total: total))
        end
        shard_yml_route(fake)

        report = github_crawler(fake, max_pages: 8).run

        queries = fake.requests.select(&.includes?("/search/code"))
        # 0..4096 was refused as too broad and replaced by both of its halves.
        queries.any?(&.includes?("size%3A0..2048")).should be_true
        queries.any?(&.includes?("size%3A2049..4096")).should be_true
        # And the open-ended tail window is still swept, so nothing above 4096
        # bytes is quietly excluded by the choice of an initial bound.
        queries.any?(&.includes?("size%3A%3E%3D4097")).should be_true
        report.status.should eq(CrawlState::Status::COMPLETED)
      end
    end

    it "reports partial when a window cannot be narrowed below the result cap" do
      FakeHost.run do |fake|
        # Every window starting at zero claims more matches than the host will
        # return, so the sweep halves it, and halves the half, until the window
        # is a single byte size that cannot be divided. That is what more than a
        # thousand root shard.yml files of the same size looks like: those
        # results really are unreachable, and no amount of splitting fixes it.
        fake.on(/\/search\/code/) do |target|
          over_cap = first_window?(target)
          FakeHost::Response.new(body: Discovery::Fixtures.github_code_search(
            over_cap ? [{"acme/router", ""}] : [] of {String, String},
            total: over_cap ? 5_000 : 0
          ))
        end
        shard_yml_route(fake, "router")

        report = github_crawler(fake, max_pages: 200).run

        # The sweep ran out of windows rather than being cut short, so it is not
        # rate limited, not interrupted and not an error. It simply has not seen
        # the whole host, and says so.
        report.status.should eq(CrawlState::Status::PARTIAL)
        report.stop_reason.should eq(CrawlState::StopReason::RESULT_CAP_TRUNCATED)
      end
    end

    it "asks GitLab for the next page the host names, rather than counting pages itself" do
      FakeHost.run do |fake|
        fake.on(/\/projects\?/) do |_target, attempt|
          if attempt == 0
            FakeHost::Response.new(
              body: Discovery::Fixtures.gitlab_projects([{"acme/router", "first"}]),
              headers: {"x-next-page" => "2", "x-total" => "2", "x-total-pages" => "2"}
            )
          else
            FakeHost::Response.new(
              body: Discovery::Fixtures.gitlab_projects([{"acme/second", "second"}]),
              headers: {"x-next-page" => "", "x-total" => "2", "x-total-pages" => "2"}
            )
          end
        end
        fake.on(/\/repository\/files\/shard\.yml\/raw/) do
          FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("router"))
        end

        crawler = Discovery::GitlabCrawler.new(base_url: fake.base_url, token: "spec-token")
        report = crawler.run

        fake.request_count(/page=2/).should eq(1)
        (report.discovered + report.updated).should eq(2)
        # Topic-scoped enumeration cannot claim to have seen the host.
        report.status.should eq(CrawlState::Status::PARTIAL)
        report.stop_reason.should eq(CrawlState::StopReason::COMPLETED_TOPIC_SCOPED)
      end
    end

    it "stops Codeberg's paging on a short page rather than looping forever" do
      FakeHost.run do |fake|
        fake.on(/\/repos\/search/) do |_target, attempt|
          repos = attempt == 0 ? Array.new(50) { |i| {"owner#{i}/repo#{i}", ""} } : [{"owner/last", ""}]
          FakeHost::Response.new(
            body: Discovery::Fixtures.codeberg_search(repos),
            headers: {"x-total-count" => "51"}
          )
        end
        fake.on(/\/raw\/shard\.yml/) do
          FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("codeberg-shard"))
        end

        crawler = Discovery::CodebergCrawler.new(base_url: fake.base_url, token: "spec-token")
        report = crawler.run

        report.pages.should eq(2)
        (report.discovered + report.updated).should eq(51)
      end
    end
  end

  describe "resuming" do
    it "picks up from the cursor instead of starting the host over" do
      FakeHost.run do |fake|
        fake.on(/\/search\/code/) do |_target, attempt|
          FakeHost::Response.new(body: Discovery::Fixtures.github_code_search(
            Array.new(100) { |i| {"owner#{attempt}#{i}/repo#{i}", ""} },
            total: 300
          ))
        end
        shard_yml_route(fake)

        # First run: one page, then stop with the cursor saved.
        first_report = github_crawler(fake, max_pages: 1).run
        first_report.status.should eq(CrawlState::Status::PARTIAL)
        first_report.stop_reason.should eq(CrawlState::StopReason::INTERRUPTED)
        cursor = first_report.cursor
        cursor.should_not be_nil

        # The cursor names the page that was not read yet, not the one just read.
        JSON.parse(cursor.not_nil!)["page"].as_i.should eq(2)

        fake.requests.clear

        # Second run, handed that cursor: the first thing it asks for is page 2,
        # so the work of the first run is not repeated. A crawl that restarted
        # here would read page 1 forever on any host that keeps interrupting it.
        github_crawler(fake, max_pages: 1).run(cursor)

        queries = fake.requests.select(&.includes?("/search/code"))
        queries.first.should contain("page=2")
      end
    end

    it "throws away a cursor it cannot read rather than resuming from a guess" do
      FakeHost.run do |fake|
        fake.on(/\/search\/code/) do
          FakeHost::Response.new(body: Discovery::Fixtures.github_code_search([{"o/r", ""}], total: 1))
        end
        shard_yml_route(fake)

        crawler = github_crawler(fake, max_pages: 1)
        crawler.run("this is not json")

        # Starting the host over is recoverable. Resuming from a misread position
        # would skip pages and nobody would know.
        fake.requests.first.should contain("page=1")
      end
    end
  end

  describe "rate limits" do
    it "waits the interval the host asked for and then carries on" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new

        fake.on(/\/search\/code/) do |_target, attempt|
          if attempt == 0
            # GitHub's secondary limit: 403 with Retry-After.
            FakeHost::Response.new(
              status: 403,
              body: %({"message":"You have exceeded a secondary rate limit"}),
              headers: {"Retry-After" => "7"}
            )
          else
            FakeHost::Response.new(body: Discovery::Fixtures.github_code_search([{"acme/router", ""}], total: 1))
          end
        end
        shard_yml_route(fake, "router")

        crawler = github_crawler(fake, sleeper: sleeper)
        report = crawler.run

        # The remainder was not dropped: it retried and finished.
        sleeper.waits.should eq([7.seconds])
        report.discovered.should eq(1)
        report.status.should eq(CrawlState::Status::COMPLETED)
      end
    end

    it "waits until the reset the host published when there is no Retry-After" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new
        reset_at = Time.utc.to_unix + 30

        fake.on(/\/search\/code/) do |_target, attempt|
          if attempt == 0
            FakeHost::Response.new(
              status: 403,
              body: %({"message":"API rate limit exceeded"}),
              headers: {
                "x-ratelimit-remaining" => "0",
                "x-ratelimit-reset"     => reset_at.to_s,
                "x-ratelimit-resource"  => "search",
              }
            )
          else
            FakeHost::Response.new(body: Discovery::Fixtures.github_code_search([{"acme/router", ""}], total: 1))
          end
        end
        shard_yml_route(fake, "router")

        report = github_crawler(fake, sleeper: sleeper).run

        sleeper.waits.size.should eq(1)
        sleeper.waits.first.should be_close(30.seconds, 3.seconds)
        report.status.should eq(CrawlState::Status::COMPLETED)
      end
    end

    it "stops as partial with the cursor intact when the wait is longer than it will hold" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new

        fake.on(/\/search\/code/) do |_target, attempt|
          if attempt == 0
            FakeHost::Response.new(body: Discovery::Fixtures.github_code_search(
              Array.new(100) { |i| {"owner#{i}/repo#{i}", ""} },
              total: 300
            ))
          else
            # An hour is longer than this crawl will sit and wait.
            FakeHost::Response.new(
              status: 429,
              body: %({"message":"Too many requests"}),
              headers: {"Retry-After" => "3600"}
            )
          end
        end
        shard_yml_route(fake)

        report = github_crawler(fake, sleeper: sleeper).run

        # This is the case the requirement is really about: the sweep is not
        # finished, so it must not be recorded as if it were.
        report.status.should eq(CrawlState::Status::PARTIAL)
        report.stop_reason.should eq(CrawlState::StopReason::RATE_LIMITED)
        report.cursor.should_not be_nil
        # The first page's work was kept.
        (report.discovered + report.updated).should eq(100)
      end
    end

    it "retries a transient server error with backoff" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new

        fake.on(/\/search\/code/) do |_target, attempt|
          if attempt < 2
            FakeHost::Response.new(status: 502, body: %({"message":"Bad gateway"}))
          else
            FakeHost::Response.new(body: Discovery::Fixtures.github_code_search([{"acme/router", ""}], total: 1))
          end
        end
        shard_yml_route(fake, "router")

        report = github_crawler(fake, sleeper: sleeper).run

        sleeper.waits.size.should eq(2)
        # Exponential, so the second wait is longer than the first.
        (sleeper.waits[1] > sleeper.waits[0]).should be_true
        report.status.should eq(CrawlState::Status::COMPLETED)
        report.discovered.should eq(1)
      end
    end

    it "does not mistake a plain 403 for throttling" do
      FakeHost.run do |fake|
        sleeper = RecordedSleeper.new

        fake.on(/\/search\/code/) do
          # A bad token, not a rate limit. Retrying this forever spends nothing
          # but time and hides the real problem.
          FakeHost::Response.new(status: 403, body: %({"message":"Bad credentials"}))
        end

        report = github_crawler(fake, sleeper: sleeper).run

        sleeper.waits.should be_empty
        report.status.should eq(CrawlState::Status::FAILED)
        report.stop_reason.should eq(CrawlState::StopReason::ERROR)
        report.error.to_s.should contain("403")
      end
    end
  end

  describe "the shard.yml signal" do
    it "registers a repository that has one and skips a repository that does not" do
      FakeHost.run do |fake|
        single_window_search(fake, [{"acme/router", "a router"}, {"acme/not-a-shard", "an app"}])
        fake.on(/acme\/router\/contents\/shard\.yml/) do
          FakeHost::Response.new(body: Discovery::Fixtures.github_contents(Discovery::Fixtures.shard_yml("router")))
        end
        fake.on(/acme\/not-a-shard\/contents\/shard\.yml/) do
          # The search index can be stale, so presence is confirmed at the source.
          FakeHost::Response.new(status: 404, body: %({"message":"Not Found"}))
        end

        report = github_crawler(fake).run

        report.discovered.should eq(1)
        report.skipped.should eq(1)
        ShardQuery.new.canonical_slug("github.com/acme/router").first?.should_not be_nil
        ShardQuery.new.canonical_slug("github.com/acme/not-a-shard").first?.should be_nil
      end
    end

    it "takes the shard's name from shard.yml, not from the repository name" do
      FakeHost.run do |fake|
        single_window_search(fake, [{"acme/router.cr", ""}])
        fake.on(/\/contents\/shard\.yml/) do
          FakeHost::Response.new(body: Discovery::Fixtures.github_contents(Discovery::Fixtures.shard_yml("router")))
        end

        github_crawler(fake).run

        shard = ShardQuery.new.canonical_slug("github.com/acme/router.cr").first?
        shard.should_not be_nil
        shard.not_nil!.name.should eq("router")
        shard.not_nil!.repo.should eq("router.cr")
      end
    end
  end

  describe "seeing the same repository twice" do
    it "updates the row it already has rather than adding another" do
      FakeHost.run do |fake|
        descriptions = ["first description", "second description"]

        single_window_search(fake, [{"acme/router", "a description the crawler ignores"}])
        fake.on(/\/contents\/shard\.yml/) do |_target, attempt|
          yml = Discovery::Fixtures.shard_yml("router", descriptions[Math.min(attempt, 1)])
          FakeHost::Response.new(body: Discovery::Fixtures.github_contents(yml))
        end

        first = github_crawler(fake).run
        first.discovered.should eq(1)
        first.updated.should eq(0)

        second = github_crawler(fake).run
        second.discovered.should eq(0)
        second.updated.should eq(1)

        rows = ShardQuery.new.canonical_slug("github.com/acme/router").to_a
        rows.size.should eq(1)
        rows.first.description.should eq("second description")
      end
    end

    it "keys on identity, so the same name on two hosts is two shards" do
      FakeHost.run do |fake|
        single_window_search(fake, [{"acme/router", ""}])
        fake.on(/\/contents\/shard\.yml/) do
          FakeHost::Response.new(body: Discovery::Fixtures.github_contents(Discovery::Fixtures.shard_yml("router")))
        end
        fake.on(/\/projects\?/) do
          FakeHost::Response.new(
            body: Discovery::Fixtures.gitlab_projects([{"other/router", ""}]),
            headers: {"x-next-page" => ""}
          )
        end
        fake.on(/\/repository\/files\/shard\.yml\/raw/) do
          FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("router"))
        end

        github_crawler(fake).run
        Discovery::GitlabCrawler.new(base_url: fake.base_url, token: "spec-token").run

        # Two repositories that both call themselves "router". Before identity
        # this was one row and a uniqueness error.
        ShardQuery.new.name("router").to_a.size.should eq(2)
        ShardQuery.new.canonical_slug("github.com/acme/router").first?.should_not be_nil
        ShardQuery.new.canonical_slug("gitlab.com/other/router").first?.should_not be_nil
      end
    end

    it "marks a known repository that has lost its shard.yml, rather than leaving it looking live" do
      FakeHost.run do |fake|
        present = [true]

        single_window_search(fake, [{"acme/router", ""}])
        fake.on(/\/contents\/shard\.yml/) do
          if present.first
            FakeHost::Response.new(body: Discovery::Fixtures.github_contents(Discovery::Fixtures.shard_yml("router")))
          else
            FakeHost::Response.new(status: 404, body: %({"message":"Not Found"}))
          end
        end

        github_crawler(fake).run
        shard = ShardQuery.new.canonical_slug("github.com/acme/router").first?
        shard.not_nil!.unavailable?.should be_false

        present[0] = false
        report = github_crawler(fake).run

        report.unavailable.should eq(1)
        marked = ShardQuery.new.canonical_slug("github.com/acme/router").first?
        # The row stays: downloads, dependency edges and inbound links point at it.
        marked.should_not be_nil
        marked.not_nil!.unavailable?.should be_true
      end
    end

    it "clears the mark when the repository comes back" do
      FakeHost.run do |fake|
        present = [false]

        single_window_search(fake, [{"acme/router", ""}])
        fake.on(/\/contents\/shard\.yml/) do
          if present.first
            FakeHost::Response.new(body: Discovery::Fixtures.github_contents(Discovery::Fixtures.shard_yml("router")))
          else
            FakeHost::Response.new(status: 404, body: %({"message":"Not Found"}))
          end
        end

        ShardIdentity.upsert(
          host: "github.com", owner: "acme", repo: "router",
          repository_url: "https://github.com/acme/router", name: "router"
        )
        ShardIdentity.mark_unavailable(host: "github.com", owner: "acme", repo: "router", reason: "spec")

        present[0] = true
        github_crawler(fake).run

        ShardQuery.new.canonical_slug("github.com/acme/router").first?.not_nil!.unavailable?.should be_false
      end
    end
  end

  describe "a GitLab project in a subgroup" do
    it "is skipped and counted, not stored half-identified" do
      FakeHost.run do |fake|
        fake.on(/\/projects\?/) do
          FakeHost::Response.new(
            body: Discovery::Fixtures.gitlab_projects([
              {"group/subgroup/nested", "a nested project"},
              {"acme/flat", "a flat one"},
            ]),
            headers: {"x-next-page" => ""}
          )
        end
        fake.on(/\/repository\/files\/shard\.yml\/raw/) do
          FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("flat"))
        end

        report = Discovery::GitlabCrawler.new(base_url: fake.base_url, token: "spec-token").run

        # A three-segment identity cannot express four path segments, and a made
        # up identity is a row no URL leads back to.
        report.skipped.should eq(1)
        report.discovered.should eq(1)
        ShardQuery.new.canonical_slug("gitlab.com/acme/flat").first?.should_not be_nil
        ShardQuery.new.host("gitlab.com").to_a.size.should eq(1)
      end
    end
  end
end
