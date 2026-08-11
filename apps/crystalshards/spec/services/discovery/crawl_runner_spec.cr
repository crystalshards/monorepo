require "../../spec_helper"

# The runner is what makes a sweep durable: it refuses to start without the
# host's token, writes the cursor down after every page, and records whether the
# result can be trusted as a complete view of the host.
private def with_tokens(tokens : Hash(String, String), &)
  Discovery::Credentials.source = tokens
  begin
    yield
  ensure
    Discovery::Credentials.source = nil
  end
end

private def without_tokens(&)
  # An empty table is "no token is configured anywhere", as distinct from nil,
  # which reads the real environment and would make this spec depend on whether
  # the machine running it happens to export GITHUB_TOKEN.
  Discovery::Credentials.source = {} of String => String
  begin
    yield
  ensure
    Discovery::Credentials.source = nil
  end
end

describe Discovery::CrawlRunner do
  describe "what discovery covers" do
    it "names the hosts it crawls and the ones it does not, with the reason" do
      # The claim being defended is "the indexer finds all shards on all git
      # hosts". This is where that boundary is written down rather than inferred
      # from which files happen to exist.
      Discovery::CrawlRunner::HOSTS.should eq(["github.com", "gitlab.com", "codeberg.org", "bitbucket.org"])

      summary = Discovery::CrawlRunner.coverage_summary
      summary.should contain("github.com")
      summary.should contain("gitlab.com")
      summary.should contain("codeberg.org")

      # These are not gaps. There is no global index of every git, Mercurial or
      # Fossil repository, so there is nothing a crawler could enumerate.
      ["generic git", "mercurial", "fossil"].each do |protocol|
        Discovery::CrawlRunner::SUBMISSION_ONLY[protocol].should contain("protocol, not a host")
      end

      # Bitbucket is no longer a gap, and is also not a host the registry can
      # claim to have seen.
      Discovery::CrawlRunner::SUBMISSION_ONLY.has_key?("bitbucket.org").should be_false
    end

    it "says plainly that bitbucket is crawled and still never complete" do
      summary = Discovery::CrawlRunner.coverage_summary

      # The property this whole subsystem is defending: a partial view is never
      # presented as a complete one. Listing bitbucket.org among "crawled hosts"
      # and stopping there would do exactly that.
      summary.should contain("Crawled but never complete:")
      summary.should contain("bitbucket.org")
      summary.should contain("410 Gone")
      summary.should contain("CHANGE-2770")
      summary.should contain("no global enumeration")
      summary.should_not contain("Crawled hosts: github.com, gitlab.com, codeberg.org, bitbucket.org")
    end

    it "counts the registered workspaces, so the reason cannot read as coverage" do
      Discovery::CrawlRunner.coverage_summary.should contain("none registered")

      SaveBitbucketWorkspace.create!(slug: "acme")

      summary = Discovery::CrawlRunner.coverage_summary
      summary.should contain("1 enabled")
      summary.should contain("only by being submitted")
    end

    it "refuses a host it does not crawl instead of pretending to sweep it" do
      report = Discovery::CrawlRunner.run("git.invalid.test")

      report.status.should eq(CrawlState::Status::FAILED)
      report.stop_reason.should eq(CrawlState::StopReason::UNSUPPORTED_HOST)
      CrawlStateQuery.new.for_host("git.invalid.test").not_nil!.trustworthy?.should be_false
    end
  end

  describe "a host with no token configured" do
    it "refuses to start and says which variable is missing" do
      without_tokens do
        report = Discovery::CrawlRunner.run("github.com")

        report.status.should eq(CrawlState::Status::FAILED)
        report.stop_reason.should eq(CrawlState::StopReason::TOKEN_MISSING)
        report.error.to_s.should contain("GITHUB_TOKEN")
        # Nothing was requested, so nothing was half-crawled.
        report.pages.should eq(0)
        report.requests.should eq(0)
      end
    end

    it "records the refusal on the host's row instead of leaving it silent" do
      without_tokens do
        Discovery::CrawlRunner.run("gitlab.com")

        state = CrawlStateQuery.new.for_host("gitlab.com")
        state.should_not be_nil
        state.not_nil!.status.should eq(CrawlState::Status::FAILED)
        state.not_nil!.stop_reason.should eq(CrawlState::StopReason::TOKEN_MISSING)
        state.not_nil!.last_error.to_s.should contain("GITLAB_TOKEN")
        state.not_nil!.trustworthy?.should be_false
      end
    end

    it "keeps a cursor it already had, so configuring the token resumes rather than restarts" do
      SaveCrawlState.create!(
        host: "codeberg.org",
        status: CrawlState::Status::PARTIAL,
        cursor: "4",
        stop_reason: CrawlState::StopReason::RATE_LIMITED,
      )

      without_tokens do
        Discovery::CrawlRunner.run("codeberg.org")
      end

      CrawlStateQuery.new.for_host("codeberg.org").not_nil!.cursor.should eq("4")
    end

    it "names every host's variable in the message it fails with" do
      without_tokens do
        Discovery::Credentials.missing_message("github.com").should contain("GITHUB_TOKEN")
        Discovery::Credentials.missing_message("gitlab.com").should contain("GITLAB_TOKEN")
        Discovery::Credentials.missing_message("codeberg.org").should contain("CODEBERG_TOKEN")
      end
    end

    it "reads the token from the environment variable for the host" do
      with_tokens({"GITHUB_TOKEN" => "gh-token"}) do
        Discovery::Credentials.configured?("github.com").should be_true
        Discovery::Credentials.token_for("github.com").should eq("gh-token")
        Discovery::Credentials.configured?("gitlab.com").should be_false

        expect_raises(Discovery::MissingTokenError, /GITLAB_TOKEN/) do
          Discovery::Credentials.token_for("gitlab.com")
        end
      end
    end

    it "needs both halves of the bitbucket credential, not just the secret" do
      # The app password alone authenticates as nobody: Basic needs the account
      # it belongs to. Treating the secret as sufficient starts a sweep that
      # 401s on its first request and reports a host with no shards on it.
      with_tokens({"BITBUCKET_APP_PASSWORD" => "secret"}) do
        Discovery::Credentials.configured?("bitbucket.org").should be_false
      end

      with_tokens({"BITBUCKET_APP_PASSWORD" => "secret", "BITBUCKET_USERNAME" => "account"}) do
        Discovery::Credentials.configured?("bitbucket.org").should be_true
        Discovery::Credentials.username_for?("bitbucket.org").should eq("account")
      end

      without_tokens do
        message = Discovery::Credentials.missing_message("bitbucket.org")
        message.should contain("BITBUCKET_USERNAME")
        message.should contain("BITBUCKET_APP_PASSWORD")
      end
    end
  end

  describe "a host the registry does not crawl" do
    it "is refused rather than crawled generically" do
      report = Discovery::CrawlRunner.run("git.example.test")

      report.status.should eq(CrawlState::Status::FAILED)
      report.stop_reason.should eq(CrawlState::StopReason::UNSUPPORTED_HOST)
    end
  end

  describe "recording a sweep" do
    it "saves the cursor after every page, not just at the end" do
      FakeHost.run do |fake|
        cursors = [] of String?

        fake.on(/\/projects\?/) do |_target, attempt|
          next_page = attempt < 2 ? (attempt + 2).to_s : ""
          FakeHost::Response.new(
            body: Discovery::Fixtures.gitlab_projects([{"acme/page#{attempt}", ""}]),
            headers: {"x-next-page" => next_page}
          )
        end
        fake.on(/\/repository\/files\/shard\.yml\/raw/) do
          FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("paged"))
        end

        crawler = Discovery::GitlabCrawler.new(base_url: fake.base_url, token: "spec-token")
        crawler.on_page = ->(cursor : String?) do
          cursors << cursor
          nil
        end
        crawler.run

        # Three pages, and the position was published after each one. A sweep that
        # only saved at the end would restart from page one every time it was
        # interrupted, which on a throttled host means never finishing.
        cursors.should eq(["2", "3", nil])
      end
    end

    it "writes status, stop reason and counts to the host's row" do
      with_tokens({"GITLAB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          fake.on(/\/projects\?/) do
            FakeHost::Response.new(
              body: Discovery::Fixtures.gitlab_projects([{"acme/router", "a router"}]),
              headers: {"x-next-page" => ""}
            )
          end
          fake.on(/\/repository\/files\/shard\.yml\/raw/) do
            FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("router"))
          end

          report = Discovery::CrawlRunner.run("gitlab.com", base_url: fake.base_url)

          state = CrawlStateQuery.new.for_host("gitlab.com").not_nil!
          state.status.should eq(CrawlState::Status::PARTIAL)
          state.stop_reason.should eq(CrawlState::StopReason::COMPLETED_TOPIC_SCOPED)
          state.discovered_count.should eq(1)
          state.cursor.should be_nil
          state.last_started_at.should_not be_nil
          # Topic-scoped coverage is not a complete view of the host, so it is not
          # recorded as one even though the sweep ran to the end.
          state.trustworthy?.should be_false
          report.partial?.should be_true
        end
      end
    end

    it "marks an exhaustive sweep as complete and trustworthy" do
      with_tokens({"GITHUB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          fake.on(/\/search\/code/) do
            FakeHost::Response.new(body: Discovery::Fixtures.github_code_search([{"acme/router", ""}], total: 1))
          end
          fake.on(/\/contents\/shard\.yml/) do
            FakeHost::Response.new(body: Discovery::Fixtures.github_contents(Discovery::Fixtures.shard_yml("router")))
          end

          Discovery::CrawlRunner.run("github.com", base_url: fake.base_url)

          state = CrawlStateQuery.new.for_host("github.com").not_nil!
          state.status.should eq(CrawlState::Status::COMPLETED)
          state.stop_reason.should eq(CrawlState::StopReason::COMPLETED_EXHAUSTIVE)
          state.last_completed_at.should_not be_nil
          state.trustworthy?.should be_true
        end
      end
    end

    it "resumes from the stored cursor on the next run" do
      with_tokens({"GITLAB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          fake.on(/\/projects\?/) do |_target, attempt|
            FakeHost::Response.new(
              body: Discovery::Fixtures.gitlab_projects([{"acme/repo#{attempt}", ""}]),
              headers: {"x-next-page" => attempt < 3 ? (attempt + 2).to_s : ""}
            )
          end
          fake.on(/\/repository\/files\/shard\.yml\/raw/) do
            FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("resumed"))
          end

          first = Discovery::CrawlRunner.run("gitlab.com", base_url: fake.base_url, max_pages: 1)
          first.status.should eq(CrawlState::Status::PARTIAL)
          first.stop_reason.should eq(CrawlState::StopReason::INTERRUPTED)
          CrawlStateQuery.new.for_host("gitlab.com").not_nil!.cursor.should eq("2")

          fake.requests.clear
          Discovery::CrawlRunner.run("gitlab.com", base_url: fake.base_url, max_pages: 1)

          # The second run asked for the page the cursor named.
          fake.requests.select(&.includes?("/projects")).first.should contain("page=2")
          CrawlStateQuery.new.for_host("gitlab.com").not_nil!.cursor.should eq("3")
        end
      end
    end

    it "starts the host over when asked for a fresh sweep" do
      with_tokens({"GITLAB_TOKEN" => "spec-token"}) do
        SaveCrawlState.create!(
          host: "gitlab.com",
          status: CrawlState::Status::PARTIAL,
          cursor: "7",
          discovered_count: 12_i64,
        )

        FakeHost.run do |fake|
          fake.on(/\/projects\?/) do
            FakeHost::Response.new(
              body: Discovery::Fixtures.gitlab_projects([{"acme/router", ""}]),
              headers: {"x-next-page" => ""}
            )
          end
          fake.on(/\/repository\/files\/shard\.yml\/raw/) do
            FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("router"))
          end

          Discovery::CrawlRunner.run("gitlab.com", base_url: fake.base_url, fresh: true)

          fake.requests.select(&.includes?("/projects")).first.should contain("page=1")
          state = CrawlStateQuery.new.for_host("gitlab.com").not_nil!
          # Counts describe one pass, so a pass that starts over starts them over.
          state.discovered_count.should eq(1)
        end
      end
    end

    it "accumulates counts across the runs that make up one resumed pass" do
      with_tokens({"GITLAB_TOKEN" => "spec-token"}) do
        FakeHost.run do |fake|
          fake.on(/\/projects\?/) do |_target, attempt|
            FakeHost::Response.new(
              body: Discovery::Fixtures.gitlab_projects([{"acme/repo#{attempt}", ""}]),
              headers: {"x-next-page" => attempt < 2 ? (attempt + 2).to_s : ""}
            )
          end
          fake.on(/\/repository\/files\/shard\.yml\/raw/) do |_target, attempt|
            FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("shard#{attempt}"))
          end

          Discovery::CrawlRunner.run("gitlab.com", base_url: fake.base_url, max_pages: 1)
          Discovery::CrawlRunner.run("gitlab.com", base_url: fake.base_url, max_pages: 1)

          CrawlStateQuery.new.for_host("gitlab.com").not_nil!.discovered_count.should eq(2)
        end
      end
    end
  end

  describe "the worker" do
    it "sweeps the host it was given and does not raise on a refused sweep" do
      swept = [] of {String, Bool, Int32?}

      DiscoverShardsWorker.runner = ->(host : String, fresh : Bool, max_pages : Int32?) do
        swept << {host, fresh, max_pages}
        report = Discovery::CrawlReport.new(host)
        report.status = CrawlState::Status::FAILED
        report.stop_reason = CrawlState::StopReason::TOKEN_MISSING
        report.error = "no token"
        report
      end

      begin
        DiscoverShardsWorker.new(host: "github.com", fresh: true, max_pages: 3).perform
      ensure
        DiscoverShardsWorker.runner = ->(host : String, fresh : Bool, max_pages : Int32?) do
          Discovery::CrawlRunner.run(host, fresh: fresh, max_pages: max_pages)
        end
      end

      # A missing token is not something to retry until the queue gives up.
      swept.should eq([{"github.com", true, 3}])
    end
  end

  describe "sweeping bitbucket" do
    it "writes the workspace cursor to the host's row and resumes from it next run" do
      with_tokens({"BITBUCKET_USERNAME" => "account", "BITBUCKET_APP_PASSWORD" => "secret"}) do
        SaveBitbucketWorkspace.create!(slug: "acme")
        SaveBitbucketWorkspace.create!(slug: "beta")

        FakeHost.run do |fake|
          fake.on(/\/repositories\/[^\/?]+\?/) do |target, _attempt|
            slug = target.match(/\/repositories\/([^\/?]+)\?/).try(&.[1]) || ""
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"#{slug}/router", ""}]))
          end
          fake.on(/\/src\/master\/shard\.yml/) do |target, _|
            FakeHost::Response.new(body: Discovery::Fixtures.shard_yml(target.split('/')[3]))
          end

          first = Discovery::CrawlRunner.run("bitbucket.org", base_url: fake.base_url, max_pages: 1)

          first.status.should eq(CrawlState::Status::PARTIAL)
          first.stop_reason.should eq(CrawlState::StopReason::INTERRUPTED)
          # The cursor names a workspace and a page, which is what a position in
          # a walk over several workspaces has to carry.
          CrawlStateQuery.new.for_host("bitbucket.org").not_nil!.cursor.should eq("beta:1")

          fake.requests.clear
          Discovery::CrawlRunner.run("bitbucket.org", base_url: fake.base_url, max_pages: 1)

          # Resumed at beta rather than starting the walk over at acme.
          fake.requests.find(&.includes?("/repositories/")).not_nil!.should contain("/repositories/beta")
        end
      end
    end

    it "never records the host as trustworthy, however well the sweep went" do
      with_tokens({"BITBUCKET_USERNAME" => "account", "BITBUCKET_APP_PASSWORD" => "secret"}) do
        SaveBitbucketWorkspace.create!(slug: "acme")

        FakeHost.run do |fake|
          fake.on(/\/repositories\/acme\?/) do
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"acme/router", "a router"}]))
          end
          fake.on(/\/src\/master\/shard\.yml/) do
            FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("router"))
          end

          Discovery::CrawlRunner.run("bitbucket.org", base_url: fake.base_url)

          state = CrawlStateQuery.new.for_host("bitbucket.org").not_nil!
          state.discovered_count.should eq(1)
          state.status.should eq(CrawlState::Status::PARTIAL)
          state.stop_reason.should eq(CrawlState::StopReason::COMPLETED_WORKSPACE_SCOPED)
          # Every workspace it was told about was swept end to end, and that is
          # still not a view of bitbucket.org.
          state.trustworthy?.should be_false
        end
      end
    end

    it "records which workspace refused, on the workspace rather than the host" do
      with_tokens({"BITBUCKET_USERNAME" => "account", "BITBUCKET_APP_PASSWORD" => "secret"}) do
        SaveBitbucketWorkspace.create!(slug: "acme")
        SaveBitbucketWorkspace.create!(slug: "beta")

        FakeHost.run do |fake|
          fake.on(/\/repositories\/acme\?/) do
            FakeHost::Response.new(status: 403, body: %({"type":"error","error":{"message":"Access denied"}}))
          end
          fake.on(/\/repositories\/beta\?/) do
            FakeHost::Response.new(body: Discovery::Fixtures.bitbucket_repositories([{"beta/parser", ""}]))
          end
          fake.on(/\/src\/master\/shard\.yml/) do
            FakeHost::Response.new(body: Discovery::Fixtures.shard_yml("parser"))
          end

          Discovery::CrawlRunner.run("bitbucket.org", base_url: fake.base_url)

          # The host has one error column, so a second failing workspace would
          # overwrite the first. The reason belongs where the workspace is
          # managed.
          BitbucketWorkspaceQuery.new.for_slug("acme").not_nil!.last_error.to_s.should contain("403")
          answered = BitbucketWorkspaceQuery.new.for_slug("beta").not_nil!
          answered.last_error.should be_nil
          answered.last_seen_at.should_not be_nil
        end
      end
    end

    it "refuses to sweep when no workspace is registered instead of reporting an empty host" do
      with_tokens({"BITBUCKET_USERNAME" => "account", "BITBUCKET_APP_PASSWORD" => "secret"}) do
        FakeHost.run do |fake|
          report = Discovery::CrawlRunner.run("bitbucket.org", base_url: fake.base_url)

          report.discovered.should eq(0)
          report.stop_reason.should eq(CrawlState::StopReason::NO_WORKSPACES_REGISTERED)
          CrawlStateQuery.new.for_host("bitbucket.org").not_nil!.trustworthy?.should be_false
        end
      end
    end
  end
end
