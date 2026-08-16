require "../../spec_helper"

# Required directly. src/app.cr pulls services in transitively, through whatever
# action or worker uses them, and nothing in the web app runs a sweep: this module
# exists for a Cloud Run Job that never boots Lucky. Requiring it here rather than
# adding it to the app keeps it out of the server binary, which is the same reason
# src/discover_shards.cr does not require src/app.cr.
require "../../../src/services/discovery/sweep"

# The driver behind the discover-shards Cloud Run Job.
#
# Nothing here touches a host. The per-host sweep goes through Sweep.runner, so
# these exercise what the Job decides: which hosts it looks at, what it does with
# the ones it cannot, what it hands the runner, and what exit code an operator and
# a dashboard get out the other end.
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
  # which reads the real environment and would make these specs depend on whether
  # the machine running them happens to export GITHUB_TOKEN.
  Discovery::Credentials.source = {} of String => String
  begin
    yield
  ensure
    Discovery::Credentials.source = nil
  end
end

private def default_runner : Proc(String, Bool, Int32?, Discovery::CrawlReport)
  ->(host : String, fresh : Bool, max_pages : Int32?) do
    Discovery::CrawlRunner.run(host, fresh: fresh, max_pages: max_pages)
  end
end

private alias SweptCall = {String, Bool, Int32?}

private def default_seeder : Proc(Discovery::Sweep::Options, Discovery::CrawlReport)
  ->(options : Discovery::Sweep::Options) do
    Discovery::CrawlRunner.run_high_value(fresh: options.fresh, max_pages: options.high_value_pages)
  end
end

# Replaces the per-host sweep with `answer` and records every call in `swept`, so a
# spec can assert what the driver asked for as well as what it did with the reply.
#
# The high-value seeding pass is swapped at the same time, and it has to be. It is
# gated on github.com's credential exactly as CrawlRunner is, so a spec that sets
# GITHUB_TOKEN and leaves the seeder alone sends a real request to api.github.com
# with a fake token. `seed` records the options it was handed and answers with
# `seeded`, which defaults to nothing so the existing expectations about `reports`
# and `failures` describe hosts only.
private def with_runner(
  answer : Proc(String, Discovery::CrawlReport),
  swept : Array(SweptCall) = [] of SweptCall,
  seed : Array(Discovery::Sweep::Options) = [] of Discovery::Sweep::Options,
  seeded : Discovery::CrawlReport? = nil,
  &
)
  Discovery::Sweep.runner = ->(host : String, fresh : Bool, max_pages : Int32?) do
    swept << {host, fresh, max_pages}
    answer.call(host)
  end

  Discovery::Sweep.seeder = ->(options : Discovery::Sweep::Options) do
    seed << options
    seeded || report_for(
      Discovery::HighValueCrawler::STATE_KEY,
      status: CrawlState::Status::PARTIAL,
      stop_reason: CrawlState::StopReason::INTERRUPTED,
    )
  end

  begin
    yield
  ensure
    Discovery::Sweep.runner = default_runner
    Discovery::Sweep.seeder = default_seeder
  end
end

private def report_for(
  host : String,
  status : String = CrawlState::Status::COMPLETED,
  stop_reason : String? = CrawlState::StopReason::COMPLETED_EXHAUSTIVE,
  failed : Int32 = 0,
  error : String? = nil,
) : Discovery::CrawlReport
  report = Discovery::CrawlReport.new(host)
  report.status = status
  report.stop_reason = stop_reason
  report.failed = failed
  report.error = error
  report
end

private def completing : Proc(String, Discovery::CrawlReport)
  ->(host : String) { report_for(host) }
end

private def options(max_pages : Int32 = 10, fresh : Bool = false) : Discovery::Sweep::Options
  Discovery::Sweep::Options.new(max_pages: max_pages, fresh: fresh)
end

private def rendered(result : Discovery::Sweep::Result) : String
  String.build { |io| Discovery::Sweep.render(result, io) }
end

private def empty_result(opts : Discovery::Sweep::Options) : Discovery::Sweep::Result
  Discovery::Sweep::Result.new(
    [] of Discovery::CrawlReport,
    [] of Discovery::Sweep::Skip,
    opts
  )
end

describe Discovery::Sweep do
  describe "a host whose credential is required" do
    it "is skipped rather than crawled, and the run still succeeds" do
      swept = [] of SweptCall

      result = without_tokens do
        with_runner(completing, swept) do
          Discovery::Sweep.run(options)
        end
      end

      # Only the two hosts that cannot be read anonymously sit out. GitHub's code
      # search answers an unauthenticated request with 401, and Bitbucket gives an
      # anonymous caller 60 requests an hour, so starting either without a token
      # would produce a handful of rows that read like an empty host.
      swept.map(&.[0]).should eq(["gitlab.com", "codeberg.org"])
      result.reports.map(&.host).should eq(["gitlab.com", "codeberg.org"])
      result.skips.map(&.host).should eq(["github.com", "bitbucket.org"])
      result.ok?.should be_true
      result.exit_code.should eq(0)
    end

    it "crawls the hosts whose token is optional with no credential at all" do
      # The behaviour this whole distinction exists for. gitlab.com's crawler uses
      # the topic-scoped project listing and codeberg.org's uses Forgejo's public
      # repository search; both answer anonymously, as does each one's raw
      # shard.yml fetch. Gating them on a token cost coverage and bought nothing.
      without_tokens do
        Discovery::Credentials.crawlable?("gitlab.com").should be_true
        Discovery::Credentials.crawlable?("codeberg.org").should be_true

        # Crawlable is not configured. A reader of the summary should still be
        # able to tell that no token is present.
        Discovery::Credentials.configured?("gitlab.com").should be_false
        Discovery::Credentials.configured?("codeberg.org").should be_false

        Discovery::Credentials.crawlable?("github.com").should be_false
        Discovery::Credentials.crawlable?("bitbucket.org").should be_false
      end
    end

    it "does not write a failed row for a host nobody has enabled" do
      # CrawlRunner.run records TOKEN_MISSING against the host, which is right
      # when an operator named that host and wrong when a schedule passed it. Left
      # unfiltered, a registry holding only GITHUB_TOKEN would carry permanently
      # FAILED rows describing configuration that was never wrong, which is what
      # a status page would then show as a broken indexer.
      #
      # The runner is stubbed because the two optional hosts are really crawled
      # now, and a spec about state rows must not depend on gitlab.com answering.
      without_tokens do
        with_runner(completing) { Discovery::Sweep.run(options) }
      end

      ["github.com", "bitbucket.org"].each do |host|
        CrawlStateQuery.new.for_host(host).should be_nil
      end
    end

    it "names the variable that would enable it, on its own line" do
      result = without_tokens do
        with_runner(completing) { Discovery::Sweep.run(options) }
      end
      output = rendered(result)

      output.should contain("github.com: no credential. Set GITHUB_TOKEN to crawl it.")

      # The two optional hosts are crawled, so neither may appear as a skip. A
      # line telling an operator to set GITLAB_TOKEN "to crawl it" would be false.
      output.should_not contain("gitlab.com: no credential")
      output.should_not contain("codeberg.org: no credential")
    end

    it "names both halves of a credential pair, not just the secret" do
      # BITBUCKET_APP_PASSWORD alone authenticates as nobody. A skip line naming
      # only the secret sends an operator away to set it and leaves them with a
      # still-skipped host and nothing to read that explains why.
      Discovery::Sweep.required_variables("bitbucket.org")
        .should eq(["BITBUCKET_USERNAME", "BITBUCKET_APP_PASSWORD"])

      result = with_tokens({"BITBUCKET_APP_PASSWORD" => "secret"}) do
        with_runner(completing) { Discovery::Sweep.run(options) }
      end

      rendered(result).should contain(
        "bitbucket.org: no credential. Set BITBUCKET_USERNAME and BITBUCKET_APP_PASSWORD to crawl it."
      )
      result.ok?.should be_true
    end

    it "says plainly that a run which crawled nothing still succeeded" do
      # Reachable only when every requested host required a credential, which is
      # why this asks for github.com alone rather than the default host list.
      result = without_tokens do
        with_runner(completing) { Discovery::Sweep.run(options, hosts: ["github.com"]) }
      end
      output = rendered(result)

      # The output an operator is most likely to misread. "Crawled nothing" and
      # "the sweep is broken" have to be distinguishable without reading code.
      output.should contain("Crawled: nothing.")
      output.should contain("no requested host has the credential it requires")
      output.should contain("Exit 0.")
    end
  end

  describe "a host with a credential" do
    it "crawls the configured hosts and the anonymous ones, and skips the rest" do
      swept = [] of SweptCall

      result = with_tokens({"GITHUB_TOKEN" => "gh-token"}) do
        with_runner(completing, swept) do
          Discovery::Sweep.run(options)
        end
      end

      # One token buys github.com. gitlab.com and codeberg.org need no token at
      # all, so they run beside it. bitbucket.org is the only host left out.
      swept.map(&.[0]).should eq(["github.com", "gitlab.com", "codeberg.org"])
      result.reports.map(&.host).should eq(["github.com", "gitlab.com", "codeberg.org"])
      result.skips.map(&.host).should eq(["bitbucket.org"])
      result.exit_code.should eq(0)
    end

    it "reports the crawled hosts beside the unconfigured one as a success" do
      result = with_tokens({"GITHUB_TOKEN" => "gh-token"}) do
        with_runner(completing) do
          Discovery::Sweep.run(options)
        end
      end

      rendered(result).should contain("Sweep succeeded: crawled 3 hosts, skipped 1.")
      result.ok?.should be_true
    end
  end

  describe "a configured host that fails" do
    it "fails the run" do
      failing = ->(host : String) do
        report_for(
          host,
          status: CrawlState::Status::FAILED,
          stop_reason: CrawlState::StopReason::ERROR,
          error: "502 from the host"
        )
      end

      # Scoped to one host because the subject is what a failure does to the exit
      # code, not which hosts a default run reaches.
      result = with_tokens({"GITHUB_TOKEN" => "gh-token"}) do
        with_runner(failing) { Discovery::Sweep.run(options, hosts: ["github.com"]) }
      end

      result.ok?.should be_false
      result.exit_code.should eq(1)
      result.failures.map(&.host).should eq(["github.com"])
      rendered(result).should contain("Sweep failed on github.com. Exit 1.")
    end

    it "fails the run when a host finished with failures counted against it" do
      # BitbucketCrawler counts a registered workspace that answered 403 here, and
      # Registrar counts a repository it identified as a shard which the registry
      # then refused to store. Both are things this run was configured to do and
      # could not, so exiting 0 would report a clean sweep over an access problem.
      counted = ->(host : String) { report_for(host, failed: 2) }

      result = with_tokens({"GITHUB_TOKEN" => "gh-token"}) do
        with_runner(counted) { Discovery::Sweep.run(options, hosts: ["github.com"]) }
      end

      result.ok?.should be_false
      result.exit_code.should eq(1)
      rendered(result).should contain("2 things on this host could not be recorded")
    end

    it "keeps sweeping the hosts after one that raised, and still fails the run" do
      swept = [] of SweptCall
      raising = ->(host : String) do
        raise "connection reset" if host == "github.com"
        report_for(host)
      end

      result = with_tokens({"GITHUB_TOKEN" => "gh", "GITLAB_TOKEN" => "gl"}) do
        with_runner(raising, swept) { Discovery::Sweep.run(options, hosts: ["github.com", "gitlab.com"]) }
      end

      # Letting the exception out would lose gitlab.com and, worse, lose the
      # printed summary of everything that ran before the crash.
      swept.map(&.[0]).should eq(["github.com", "gitlab.com"])
      result.reports.map(&.host).should eq(["github.com", "gitlab.com"])
      result.failures.map(&.host).should eq(["github.com"])
      result.exit_code.should eq(1)
      rendered(result).should contain("connection reset")
    end

    it "does not let one failing host hide the ones that worked" do
      mixed = ->(host : String) do
        if host == "github.com"
          report_for(host, status: CrawlState::Status::FAILED, stop_reason: CrawlState::StopReason::ERROR)
        else
          report_for(host)
        end
      end

      result = with_tokens({"GITHUB_TOKEN" => "gh", "GITLAB_TOKEN" => "gl"}) do
        with_runner(mixed) { Discovery::Sweep.run(options, hosts: ["github.com", "gitlab.com"]) }
      end

      output = rendered(result)
      output.should contain("gitlab.com: completed")
      output.should contain("A complete view of this host.")
      result.exit_code.should eq(1)
    end
  end

  describe "the bound and the cursors" do
    it "passes the bound through to every host it crawls" do
      swept = [] of SweptCall

      with_tokens({"GITHUB_TOKEN" => "gh", "GITLAB_TOKEN" => "gl"}) do
        with_runner(completing, swept) do
          Discovery::Sweep.run(options(max_pages: 4), hosts: ["github.com", "gitlab.com"])
        end
      end

      swept.should eq([{"github.com", false, 4}, {"gitlab.com", false, 4}])
    end

    it "resumes by default, so a bounded run continues rather than restarting" do
      swept = [] of SweptCall

      with_tokens({"GITHUB_TOKEN" => "gh"}) do
        with_runner(completing, swept) do
          Discovery::Sweep.run(options(max_pages: 2), hosts: ["github.com"])
        end
      end

      # `fresh` false is the whole resume story: CrawlRunner reads the saved
      # cursor unless it is told to start over. A driver that passed true every
      # run would sweep the same first two pages forever.
      swept.map(&.[1]).should eq([false])
    end

    it "starts a host over only when it is told to" do
      swept = [] of SweptCall

      with_tokens({"GITHUB_TOKEN" => "gh"}) do
        with_runner(completing, swept) do
          Discovery::Sweep.run(options(max_pages: 2, fresh: true), hosts: ["github.com"])
        end
      end

      swept.should eq([{"github.com", true, 2}])
    end

    it "hands the saved cursor to the next run, through the runner it drives" do
      # The resume path with a real crawl_states row: a previous bounded run left
      # a cursor, and this run reaches the host with that cursor still in place
      # rather than having reset it on the way in.
      SaveCrawlState.create!(
        host: "gitlab.com",
        status: CrawlState::Status::PARTIAL,
        cursor: "7",
        stop_reason: CrawlState::StopReason::INTERRUPTED,
      )

      resumed_from = [] of String?

      with_tokens({"GITLAB_TOKEN" => "gl"}) do
        Discovery::Sweep.runner = ->(host : String, fresh : Bool, _max_pages : Int32?) do
          resumed_from << (fresh ? nil : Discovery::CrawlRunner.state_for(host).try(&.cursor))
          report_for(host)
        end

        begin
          Discovery::Sweep.run(options, hosts: ["gitlab.com"])
        ensure
          Discovery::Sweep.runner = default_runner
        end
      end

      resumed_from.should eq(["7"])
    end

    it "tells the operator which way the cursors went" do
      rendered(empty_result(options))
        .should contain("Cursors: kept, every host resumes where its last run stopped.")

      rendered(empty_result(options(fresh: true)))
        .should contain("Cursors: discarded, every host swept from the beginning.")
    end
  end

  describe "reading the bound out of the environment" do
    it "defaults to a bounded run when nothing is set" do
      # The property that matters: an unset variable can never produce an
      # unbounded sweep. A sweep with no budget runs until the Job's task timeout
      # kills it, which happens mid-page, and the next run repeats that page.
      parsed = Discovery::Sweep::Options.parse(nil, nil)
      parsed.max_pages.should eq(Discovery::Sweep::DEFAULT_MAX_PAGES)
      parsed.max_pages.should be > 0
      parsed.fresh.should be_false
    end

    it "reads the bound and the restart switch" do
      Discovery::Sweep::Options.parse("25", "true")
        .should eq(Discovery::Sweep::Options.new(max_pages: 25, fresh: true))

      Discovery::Sweep::Options.parse(" 3 ", " NO ")
        .should eq(Discovery::Sweep::Options.new(max_pages: 3, fresh: false))

      Discovery::Sweep::Options.parse("", "")
        .should eq(Discovery::Sweep::Options.new(max_pages: Discovery::Sweep::DEFAULT_MAX_PAGES, fresh: false))
    end

    it "refuses a bound it cannot use rather than quietly defaulting" do
      # A typo that silently becomes the default is how an operator ends up
      # certain they changed the budget and unable to see any effect.
      ["banana", "0", "-1", "2.5"].each do |value|
        expect_raises(Discovery::Sweep::ConfigurationError, /DISCOVERY_MAX_PAGES/) do
          Discovery::Sweep::Options.parse(value, nil)
        end
      end
    end

    it "refuses a restart switch it cannot use rather than reading it as false" do
      expect_raises(Discovery::Sweep::ConfigurationError, /DISCOVERY_FRESH/) do
        Discovery::Sweep::Options.parse(nil, "maybe")
      end
    end

    it "bounds the seeding pass separately from the per-host sweep" do
      # Two bounds because the run has two shapes of work drawing on one core
      # budget. Raising the per-host bound to finish a host sooner must not
      # silently spend the seeding pass's share of the same 5000 an hour.
      parsed = Discovery::Sweep::Options.parse("20", nil, "5")
      parsed.max_pages.should eq(20)
      parsed.high_value_pages.should eq(5)

      Discovery::Sweep::Options.parse(nil, nil, nil).high_value_pages
        .should eq(Discovery::HighValueCrawler::DEFAULT_MAX_PAGES)

      expect_raises(Discovery::Sweep::ConfigurationError, /DISCOVERY_HIGH_VALUE_PAGES/) do
        Discovery::Sweep::Options.parse(nil, nil, "0")
      end
    end

    it "names the variables it reads, so terraform and this file cannot drift" do
      Discovery::Sweep::MAX_PAGES_VARIABLE.should eq("DISCOVERY_MAX_PAGES")
      Discovery::Sweep::FRESH_VARIABLE.should eq("DISCOVERY_FRESH")
      Discovery::Sweep::HIGH_VALUE_PAGES_VARIABLE.should eq("DISCOVERY_HIGH_VALUE_PAGES")
    end
  end

  describe "what the job log says" do
    it "carries the coverage boundary with the numbers" do
      result = without_tokens do
        with_runner(completing) { Discovery::Sweep.run(options) }
      end
      output = rendered(result)

      # Coverage is part of the result, not a footnote. A reader who sees a shard
      # count without it has been told something false about what the registry
      # knows.
      output.should contain("Crawled hosts:")
      output.should contain("Crawled but never complete:")
      output.should contain("bitbucket.org")
      output.should contain("Submission only:")
    end

    it "says whether the next run continues or the host is fully seen" do
      partial_gitlab = ->(host : String) do
        if host == "github.com"
          report_for(host)
        else
          report_for(host, status: CrawlState::Status::PARTIAL, stop_reason: CrawlState::StopReason::INTERRUPTED)
        end
      end

      result = with_tokens({"GITHUB_TOKEN" => "gh", "GITLAB_TOKEN" => "gl"}) do
        with_runner(partial_gitlab) { Discovery::Sweep.run(options) }
      end

      output = rendered(result)
      output.should contain("A complete view of this host.")
      output.should contain("Stopped at this run's page budget, cursor saved. The next scheduled run continues from it.")
    end

    it "distinguishes a rate limited pause from a finished host, without failing the run" do
      limited = ->(host : String) do
        report_for(host, status: CrawlState::Status::PARTIAL, stop_reason: CrawlState::StopReason::RATE_LIMITED)
      end

      result = with_tokens({"GITHUB_TOKEN" => "gh"}) do
        with_runner(limited) { Discovery::Sweep.run(options) }
      end

      rendered(result).should contain("Paused by the host's rate limit, cursor saved.")
      result.exit_code.should eq(0)
    end

    it "refuses to let a sweep that looked nowhere read as an empty host" do
      nowhere = ->(host : String) do
        report_for(host, status: CrawlState::Status::PARTIAL, stop_reason: CrawlState::StopReason::NO_WORKSPACES_REGISTERED)
      end

      result = with_tokens({"BITBUCKET_USERNAME" => "account", "BITBUCKET_APP_PASSWORD" => "secret"}) do
        with_runner(nowhere) { Discovery::Sweep.run(options, hosts: ["bitbucket.org"]) }
      end

      rendered(result).should contain("Zero found here means zero places looked, not an empty host.")
    end
  end

  describe "the high-value seeding pass" do
    it "runs before the hosts, so a run cut short has still seeded the ranking" do
      order = [] of String
      swept = [] of SweptCall
      seed = [] of Discovery::Sweep::Options

      recording = ->(host : String) do
        order << host
        report_for(host)
      end

      with_tokens({"GITHUB_TOKEN" => "gh"}) do
        Discovery::Sweep.runner = ->(host : String, _fresh : Bool, _max_pages : Int32?) do
          swept << {host, false, nil}
          recording.call(host)
        end
        Discovery::Sweep.seeder = ->(options : Discovery::Sweep::Options) do
          order << "seed"
          seed << options
          report_for(Discovery::HighValueCrawler::STATE_KEY, status: CrawlState::Status::PARTIAL,
            stop_reason: CrawlState::StopReason::INTERRUPTED)
        end

        begin
          # One host, because the subject is the order of the two phases rather
          # than which hosts the default list reaches.
          Discovery::Sweep.run(options, hosts: ["github.com"])
        ensure
          Discovery::Sweep.runner = default_runner
          Discovery::Sweep.seeder = default_seeder
        end
      end

      # Both phases spend the same core budget reading shard.yml files, so
      # whichever goes second is the one a throttled run cuts short. The
      # exhaustive sweep loses nothing by being that one: its cursor advances,
      # so a page it does not reach is where the next run starts.
      order.should eq(["seed", "github.com"])
      seed.map(&.high_value_pages).should eq([Discovery::HighValueCrawler::DEFAULT_MAX_PAGES])
    end

    it "is not one of the hosts, however the summary is read" do
      seed = [] of Discovery::Sweep::Options

      result = with_tokens({"GITHUB_TOKEN" => "gh"}) do
        with_runner(completing, seed: seed) { Discovery::Sweep.run(options, hosts: ["github.com"]) }
      end

      # A second enumeration of github.com, not a fifth host. Folding it into
      # reports would put two rows called github.com in every summary and make
      # the registry look like it crawls somewhere it does not.
      seed.size.should eq(1)
      result.reports.map(&.host).should eq(["github.com"])
      result.seed.not_nil!.host.should eq("github.com/high-value")
    end

    it "does not seed a run that was never going to reach github" do
      seed = [] of Discovery::Sweep::Options

      with_tokens({"BITBUCKET_USERNAME" => "account", "BITBUCKET_APP_PASSWORD" => "secret"}) do
        with_runner(completing, seed: seed) { Discovery::Sweep.run(options, hosts: ["bitbucket.org"]) }
      end

      # The pass reads GitHub's repository search with GitHub's credential. A
      # run that excludes the host has nothing to seed from, and one without the
      # token is already told so by the host's own skip line.
      seed.should be_empty

      without_tokens do
        with_runner(completing, seed: seed) { Discovery::Sweep.run(options) }
      end

      seed.should be_empty
    end

    it "hands the operator the bound, the cursor and the bucket it spends" do
      result = with_tokens({"GITHUB_TOKEN" => "gh"}) do
        with_runner(completing) { Discovery::Sweep.run(options) }
      end

      output = rendered(result)
      output.should contain("High-value seed (before the exhaustive sweep):")
      output.should contain("language:Crystal, topic:crystal")
      output.should contain("ranked by stars")
      # Which budget this costs. /search/repositories is the 30 a minute search
      # bucket and /search/code is the 10 a minute code_search one, so the seed
      # is not competing with the exhaustive sweep for search quota.
      output.should contain("30 a minute search")
      output.should contain("github.com/high-value")

      # And the seed is printed above the hosts, in the order they ran.
      output.index("High-value seed").not_nil!
        .should be < output.index("Crawled:").not_nil!
    end

    it "says the ranking was walked to its cap, without calling it a whole host" do
      capped = report_for(
        Discovery::HighValueCrawler::STATE_KEY,
        status: CrawlState::Status::PARTIAL,
        stop_reason: CrawlState::StopReason::COMPLETED_RANK_CAPPED,
      )

      result = with_tokens({"GITHUB_TOKEN" => "gh"}) do
        with_runner(completing, seeded: capped) { Discovery::Sweep.run(options) }
      end

      rendered(result).should contain("which is their top 1000 and not the host")
      result.exit_code.should eq(0)
    end

    it "fails the run when the seeding pass fails" do
      failing = report_for(
        Discovery::HighValueCrawler::STATE_KEY,
        status: CrawlState::Status::FAILED,
        stop_reason: CrawlState::StopReason::ERROR,
        error: "502 from the search API",
      )

      result = with_tokens({"GITHUB_TOKEN" => "gh"}) do
        with_runner(completing, seeded: failing) { Discovery::Sweep.run(options) }
      end

      # Same credential, same API, same core budget as a host. A seed that could
      # not run is a phase of this Job that did not do its job.
      result.ok?.should be_false
      result.exit_code.should eq(1)
      result.failures.map(&.host).should eq(["github.com/high-value"])
      rendered(result).should contain("Nothing was seeded from the ranking.")
    end

    it "keeps sweeping the hosts after a seeding pass that raised" do
      swept = [] of SweptCall

      result = with_tokens({"GITHUB_TOKEN" => "gh"}) do
        Discovery::Sweep.runner = ->(host : String, fresh : Bool, max_pages : Int32?) do
          swept << {host, fresh, max_pages}
          report_for(host)
        end
        Discovery::Sweep.seeder = ->(_options : Discovery::Sweep::Options) do
          raise "connection reset"
        end

        begin
          Discovery::Sweep.run(options, hosts: ["github.com"])
        ensure
          Discovery::Sweep.runner = default_runner
          Discovery::Sweep.seeder = default_seeder
        end
      end

      # Letting it out would lose every host behind it and the printed summary
      # with them, which is the same reasoning that catches a host that raises.
      swept.map(&.[0]).should eq(["github.com"])
      result.exit_code.should eq(1)
      rendered(result).should contain("connection reset")
    end
  end
end
