require "./crawl_runner"

module Discovery
  # One scheduled sweep: every host the registry holds a credential for, bounded,
  # each host resuming from its own cursor.
  #
  # This is the driver behind the `discover-shards` Cloud Run Job, and it is
  # deliberately not `CrawlRunner.run_all`, because a schedule and an operator
  # want opposite things from a missing token.
  #
  # An operator who typed `--host=gitlab.com` with no GITLAB_TOKEN asked a
  # question, and `CrawlRunner.run` answers it properly: it refuses, explains
  # which variable is missing, and writes that refusal onto the host's row. A
  # schedule that passed gitlab.com because nobody has issued a token for it yet
  # has not failed at anything. Recording a failure there would leave crawl_states
  # holding permanently FAILED rows describing configuration that was never wrong,
  # which is what a status page would then render as a broken indexer.
  #
  # So hosts are filtered on `Credentials.configured?` before the runner is
  # reached. A host without a credential comes back as a `Skip`, named, carrying
  # the variables that would enable it, and it does not touch the exit code. This
  # is the arrangement mail already has in this repo: the feature fails closed and
  # the process does not. Adding GITHUB_TOKEN is the whole switch, and no code
  # changes with it.
  module Sweep
    MAX_PAGES_VARIABLE = "DISCOVERY_MAX_PAGES"
    FRESH_VARIABLE     = "DISCOVERY_FRESH"

    # Pages per host per run when DISCOVERY_MAX_PAGES is unset.
    #
    # The bound is not a tuning knob, it is what makes a scheduled sweep work at
    # all. The crawlers persist their cursor after every page, so a run that stops
    # at its budget is a run that made progress and handed the next run a place to
    # start. A run with no budget sweeps until the Job's task timeout kills it,
    # which happens mid-page, and then the next run does that same page again.
    #
    # Ten is sized from what a page costs and from where GitHub's own ceilings sit.
    # Every crawler asks for 100 candidates a page and then reads one shard.yml per
    # candidate, so a page is roughly 101 requests and ten pages roughly 1010, which
    # fits inside GitHub's authenticated budget of 5000 requests an hour with room
    # left for the other hosts.
    #
    # Ten is also exactly one result window rather than an arbitrary round number.
    # GithubCrawler::RESULT_CAP is 1000 and PER_PAGE is 100, because the search API
    # returns at most 1000 results for any one query, so its last_page works out to
    # 10 and page eleven of a window does not exist: the crawler advances to the
    # next size window instead. A budget of ten therefore stops on a window
    # boundary rather than partway through one.
    #
    # The binding constraint is the search endpoint, not the hourly budget.
    # GET /search/code requires authentication and allows 10 requests a minute,
    # which is the code search limit specifically and not the 30 a minute the other
    # search endpoints get. Ten pages is ten of those, so a host's searches occupy
    # about a minute at the floor and HostClient waits out the rest on the host's
    # own headers.
    DEFAULT_MAX_PAGES = 10

    # The Job is misconfigured, as distinct from a host failing. Worth its own
    # type because it has its own exit code: an operator seeing it should go and
    # look at the Job's environment, not at a git host.
    class ConfigurationError < Exception
    end

    # How one run is bounded, and whether it honours the saved cursors.
    record Options, max_pages : Int32, fresh : Bool do
      def self.from_env : Options
        parse(ENV[MAX_PAGES_VARIABLE]?, ENV[FRESH_VARIABLE]?)
      end

      # Split from `from_env` so the parsing rules can be exercised without a spec
      # mutating the process environment out from under every other spec.
      def self.parse(max_pages : String?, fresh : String?) : Options
        new(max_pages: parse_max_pages(max_pages), fresh: parse_fresh(fresh))
      end

      private def self.parse_max_pages(raw : String?) : Int32
        value = raw.try(&.strip).presence
        return DEFAULT_MAX_PAGES unless value

        pages = value.to_i?
        return pages if pages && pages > 0

        # Refused rather than defaulted. A typo in the Job's environment silently
        # becoming the default bound is how an operator ends up certain they
        # changed the budget and unable to see any effect.
        raise ConfigurationError.new(
          "#{MAX_PAGES_VARIABLE} must be a positive whole number of pages, got #{value.inspect}. " \
          "It bounds one run; each host resumes from its saved cursor on the next one."
        )
      end

      private def self.parse_fresh(raw : String?) : Bool
        value = raw.try(&.strip).presence
        return false unless value

        case value.downcase
        when "true", "1", "yes" then true
        when "false", "0", "no" then false
        else
          # Same reasoning as the bound. An unrecognised value reading as false
          # would tell an operator their sweep restarted when it resumed.
          raise ConfigurationError.new(
            "#{FRESH_VARIABLE} must be true or false, got #{value.inspect}. " \
            "Setting it true discards every host's saved cursor and sweeps from the beginning."
          )
        end
      end
    end

    # A host this sweep did not look at, and what would change that.
    record Skip, host : String, variables : Array(String) do
      def to_s(io : IO) : Nil
        io << host << ": no credential. Set " << variables.join(" and ") << " to crawl it."
      end
    end

    # What one sweep did. Skips are carried alongside the reports rather than
    # folded into them, because there is no honest `CrawlReport` for a host that
    # was never asked anything.
    class Result
      getter reports : Array(CrawlReport)
      getter skips : Array(Skip)
      getter options : Options

      def initialize(@reports : Array(CrawlReport), @skips : Array(Skip), @options : Options)
      end

      # A host counts as failed when its sweep failed outright, and also when it
      # finished with failures counted against it. `report.failed` is not a
      # cosmetic tally: BitbucketCrawler increments it for a registered workspace
      # that answered 403, and Registrar increments it for a repository the
      # crawler identified as a shard and the registry then refused to store.
      # Both are "something this run was configured to do and could not", so a
      # run that exits 0 through either of them has reported a clean sweep over
      # an access problem.
      def failures : Array(CrawlReport)
        reports.select { |report| report.failed? || report.failed > 0 }
      end

      # A sweep succeeded when every host it actually crawled came back without
      # failing. A host nobody has issued a credential for is not a failure and
      # never makes one, however many of them there are.
      def ok? : Bool
        failures.empty?
      end

      def exit_code : Int32
        ok? ? 0 : 1
      end
    end

    # Test seam. The per-host sweep goes through this proc, which defaults to the
    # real runner. Specs replace it to drive the whole sweep without touching a
    # host, and must restore it in an `ensure`. The argument order is the same as
    # `DiscoverShardsWorker.runner` on purpose: two seams over the same call with
    # different orders is how a spec ends up passing max_pages as fresh.
    class_property runner : Proc(String, Bool, Int32?, CrawlReport) = ->(host : String, fresh : Bool, max_pages : Int32?) {
      CrawlRunner.run(host, fresh: fresh, max_pages: max_pages)
    }

    def self.run(options : Options, hosts : Array(String) = CrawlRunner::HOSTS) : Result
      reports = [] of CrawlReport
      skips = [] of Skip

      hosts.each do |host|
        unless Credentials.configured?(host)
          skip = Skip.new(host, required_variables(host))
          Log.info { "Discovery skipped #{skip}" }
          skips << skip
          next
        end

        reports << sweep_host(host, options)
      end

      Result.new(reports, skips, options)
    end

    # Every variable a host needs, not only its token. Bitbucket authenticates
    # with a pair, and a skip line naming just the app password would leave an
    # operator with a still-skipped host and nothing to read that explains it.
    def self.required_variables(host : String) : Array(String)
      variables = [] of String
      if account = Credentials::USERNAME_ENV[host]?
        variables << account
      end
      if token = Credentials::TOKEN_ENV[host]?
        variables << token
      end
      variables
    end

    private def self.sweep_host(host : String, options : Options) : CrawlReport
      Log.info { "Discovery sweeping #{host}, bounded to #{options.max_pages} pages#{options.fresh ? " from the beginning" : ""}" }
      @@runner.call(host, options.fresh, options.max_pages)
    rescue ex : Exception
      # A host that raised instead of reporting is still one host's problem.
      # Letting it out would lose every host after it in the list and, worse, lose
      # the printed summary of the ones before it.
      Log.error(exception: ex) { "Discovery on #{host} raised" }
      report = CrawlReport.new(host)
      report.status = CrawlState::Status::FAILED
      report.stop_reason = CrawlState::StopReason::ERROR
      report.error = ex.message.presence || ex.class.name
      report
    end

    # What the Job log says. An operator reading it should be able to tell what
    # was crawled, what was skipped and why, and whether the sweep is a complete
    # view of anything, without opening this file.
    def self.render(result : Result, io : IO = STDOUT) : Nil
      io.puts "Discovery sweep"
      io.puts "  Bound: #{result.options.max_pages} pages per host this run."
      io.puts "  Cursors: #{result.options.fresh ? "discarded, every host swept from the beginning" : "kept, every host resumes where its last run stopped"}."
      io.puts

      render_crawled(result, io)
      render_skipped(result, io)

      io.puts
      io.puts CrawlRunner.coverage_summary
      io.puts
      io.puts verdict(result)
    end

    private def self.render_crawled(result : Result, io : IO) : Nil
      if result.reports.empty?
        io.puts "Crawled: nothing."
        return
      end

      io.puts "Crawled:"
      result.reports.each do |report|
        io.puts "  #{report}"
        if note = continuation_note(report)
          io.puts "    #{note}"
        end
      end
    end

    private def self.render_skipped(result : Result, io : IO) : Nil
      return if result.skips.empty?

      io.puts "Skipped:"
      result.skips.each { |skip| io.puts "  #{skip}" }
    end

    # What the next scheduled run will do about this host, in one line. A stop
    # reason of `partial (interrupted)` is accurate and does not answer the only
    # question the Job's reader has, which is whether to wait or to intervene.
    private def self.continuation_note(report : CrawlReport) : String?
      return "Failed, so this run failed. Whatever this host had left was not swept." if report.failed?

      if (count = report.failed) > 0
        # Counted, so the sweep carried on and the rest of the host was still
        # crawled, but this run is not a success. A refused workspace and a
        # repository the registry would not store both land in this counter, and
        # the log lines above this summary name each one individually.
        return "#{count} #{count == 1 ? "thing" : "things"} on this host could not be recorded, so this run failed. " \
               "The lines above name each one."
      end

      return "A complete view of this host." if report.complete?

      case report.stop_reason
      when CrawlState::StopReason::INTERRUPTED
        "Stopped at this run's page budget, cursor saved. The next scheduled run continues from it."
      when CrawlState::StopReason::RATE_LIMITED
        "Paused by the host's rate limit, cursor saved. The next scheduled run continues from it."
      when CrawlState::StopReason::NO_WORKSPACES_REGISTERED
        "Looked nowhere: no workspaces are registered. Zero found here means zero places looked, not an empty host."
      else
        # COMPLETED_TOPIC_SCOPED, COMPLETED_WORKSPACE_SCOPED and
        # RESULT_CAP_TRUNCATED all mean one thing to a scheduler: it asked for
        # everything this host will offer and that is still not the whole host.
        # Which of the three, and why each falls short, is in the coverage
        # summary printed below rather than restated per host.
        "Asked for everything this host will offer, which is less than the whole host. See coverage below."
      end
    end

    private def self.verdict(result : Result) : String
      failures = result.failures

      unless failures.empty?
        return "Sweep failed on #{failures.map(&.host).join(", ")}. Exit #{result.exit_code}."
      end

      if result.reports.empty?
        return "Sweep succeeded and crawled nothing: no host has a credential. That is configuration, " \
               "not an error, so this run is a success. Set the variables listed above and the next run crawls those hosts. Exit 0."
      end

      hosts = result.reports.size == 1 ? "1 host" : "#{result.reports.size} hosts"
      "Sweep succeeded: crawled #{hosts}, skipped #{result.skips.size}. Exit #{result.exit_code}."
    end
  end
end
