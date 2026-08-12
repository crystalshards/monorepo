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
    MAX_PAGES_VARIABLE        = "DISCOVERY_MAX_PAGES"
    FRESH_VARIABLE            = "DISCOVERY_FRESH"
    HIGH_VALUE_PAGES_VARIABLE = "DISCOVERY_HIGH_VALUE_PAGES"

    # Which rate-limit bucket a page of the seeding pass comes out of. Measured
    # live against an authenticated token: GET /search/repositories reports
    # x-ratelimit-resource: search with a limit of 30 a minute, while
    # GET /search/code, which the exhaustive sweep is obliged to use, reports
    # code_search with a limit of 10. Naming the bucket in the Job's log is the
    # difference between an operator reading the seed as "eating the crawl's
    # search budget" and reading what is true.
    SEARCH_LIMIT = "30 a minute search"

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
    #
    # Two bounds, because the run has two shapes of work. `max_pages` bounds the
    # exhaustive per-host sweep, which walks a size partition and must eventually
    # cover it. `high_value_pages` bounds the star-ranked seeding pass, which
    # walks a ranking that has 20 pages in total and then starts again. They are
    # separate numbers because raising one to cover a host faster should not
    # silently spend the other's share of the same core budget.
    record Options,
      max_pages : Int32,
      fresh : Bool,
      high_value_pages : Int32 = HighValueCrawler::DEFAULT_MAX_PAGES do
      def self.from_env : Options
        parse(ENV[MAX_PAGES_VARIABLE]?, ENV[FRESH_VARIABLE]?, ENV[HIGH_VALUE_PAGES_VARIABLE]?)
      end

      # Split from `from_env` so the parsing rules can be exercised without a spec
      # mutating the process environment out from under every other spec.
      def self.parse(max_pages : String?, fresh : String?, high_value_pages : String? = nil) : Options
        new(
          max_pages: parse_max_pages(max_pages),
          fresh: parse_fresh(fresh),
          high_value_pages: parse_high_value_pages(high_value_pages),
        )
      end

      private def self.parse_max_pages(raw : String?) : Int32
        pages(raw) do |value|
          "#{MAX_PAGES_VARIABLE} must be a positive whole number of pages, got #{value}. " \
          "It bounds one run; each host resumes from its saved cursor on the next one."
        end || DEFAULT_MAX_PAGES
      end

      private def self.parse_high_value_pages(raw : String?) : Int32
        pages(raw) do |value|
          "#{HIGH_VALUE_PAGES_VARIABLE} must be a positive whole number of pages, got #{value}. " \
          "It bounds the star-ranked seeding pass, which walks its own cursor through the " \
          "ranking and is separate from the exhaustive per-host sweep."
        end || HighValueCrawler::DEFAULT_MAX_PAGES
      end

      # A page count, or nil when the variable is unset so the caller's default
      # applies. A variable that IS set and unusable is refused rather than
      # defaulted: a typo in the Job's environment silently becoming the default
      # bound is how an operator ends up certain they changed the budget and
      # unable to see any effect.
      private def self.pages(raw : String?, &complaint : String -> String) : Int32?
        value = raw.try(&.strip).presence
        return nil unless value

        count = value.to_i?
        return count if count && count > 0

        raise ConfigurationError.new(complaint.call(value.inspect))
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
    #
    # `seed` is the high-value pass and is deliberately not one of `reports`. It
    # is a second enumeration of github.com rather than another host, so folding
    # it in would make the registry look like it crawls five hosts and would put
    # two rows called github.com in every summary.
    class Result
      getter reports : Array(CrawlReport)
      getter skips : Array(Skip)
      getter options : Options
      getter seed : CrawlReport?

      def initialize(
        @reports : Array(CrawlReport),
        @skips : Array(Skip),
        @options : Options,
        @seed : CrawlReport? = nil,
      )
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
        # The seed is held to the same standard as a host. It runs with the same
        # credential against the same API, so a seed that failed outright, or
        # that identified shards the registry then refused to store, is the same
        # kind of problem and must not exit 0.
        candidates = reports.dup
        if pass = seed
          candidates << pass
        end

        candidates.select { |report| report.failed? || report.failed > 0 }
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

    # Test seam for the high-value pass, separate from `runner` because it takes
    # the whole options rather than a host. A spec that replaces `runner` MUST
    # replace this too: the pass is credential-gated on github.com exactly as
    # CrawlRunner is, so a spec that sets GITHUB_TOKEN and leaves this alone
    # sends a real request to api.github.com with a fake token.
    class_property seeder : Proc(Options, CrawlReport) = ->(options : Options) {
      CrawlRunner.run_high_value(fresh: options.fresh, max_pages: options.high_value_pages)
    }

    # The high-value pass runs FIRST, and the order is the point of it.
    #
    # Both phases spend the same core budget on reading shard.yml files, so
    # whichever runs second is the one that gets cut short when a run is
    # throttled or the Job's timeout lands. Putting the star ranking first means
    # a run that only half completes has still added the shards people have
    # heard of. The exhaustive sweep loses nothing by going second: its cursor
    # advances monotonically, so a page it does not reach this run is the page
    # the next run starts on.
    def self.run(options : Options, hosts : Array(String) = CrawlRunner::HOSTS) : Result
      reports = [] of CrawlReport
      skips = [] of Skip

      seed = seed_high_value(options, hosts)

      hosts.each do |host|
        unless Credentials.configured?(host)
          skip = Skip.new(host, required_variables(host))
          Log.info { "Discovery skipped #{skip}" }
          skips << skip
          next
        end

        reports << sweep_host(host, options)
      end

      Result.new(reports, skips, options, seed)
    end

    # Nil when this run was never going to reach github.com: the pass reads
    # GitHub's repository search with GitHub's credential, so a run without that
    # host or without that token has nothing to seed from. The host's own skip
    # line already names the variable, so there is nothing further to say here.
    private def self.seed_high_value(options : Options, hosts : Array(String)) : CrawlReport?
      return nil unless hosts.includes?(HighValueCrawler::HOST)
      return nil unless Credentials.configured?(HighValueCrawler::HOST)

      Log.info do
        "Discovery seeding from GitHub's star ranking, bounded to #{options.high_value_pages} " \
        "pages of 100#{options.fresh ? ", from the top" : ""}"
      end
      @@seeder.call(options)
    rescue ex : Exception
      # Same reasoning as a host that raised: the seed is one phase, and losing
      # the sweep behind it, plus the printed summary, would be worse than a
      # recorded failure.
      Log.error(exception: ex) { "Discovery high-value seeding raised" }
      report = CrawlReport.new(HighValueCrawler::STATE_KEY)
      report.status = CrawlState::Status::FAILED
      report.stop_reason = CrawlState::StopReason::ERROR
      report.error = ex.message.presence || ex.class.name
      report
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

      render_seed(result, io)
      render_crawled(result, io)
      render_skipped(result, io)

      io.puts
      io.puts CrawlRunner.coverage_summary
      io.puts
      io.puts verdict(result)
    end

    # The seeding pass, printed above the hosts because it ran above them.
    #
    # It gets its own block rather than a line among the hosts because what it
    # covers is a different claim: not "this much of github.com", but "the top
    # of the star ranking, which is where the shards anyone has heard of are".
    private def self.render_seed(result : Result, io : IO) : Nil
      seed = result.seed
      return unless seed

      io.puts "High-value seed (before the exhaustive sweep):"
      io.puts "  #{seed}"
      io.puts "  Seeds: #{HighValueCrawler::SEEDS.join(", ")} on GitHub's repository search, ranked by stars."
      io.puts "  Bound: #{result.options.high_value_pages} pages of #{HighValueCrawler::PER_PAGE} this run, " \
              "one search request each from the #{SEARCH_LIMIT} bucket, plus one contents request per candidate."
      io.puts "  Cursor: its own crawl_states row, #{HighValueCrawler::STATE_KEY}, so the exhaustive sweep's position is untouched."
      if note = seed_note(seed)
        io.puts "  #{note}"
      end
      io.puts
    end

    private def self.seed_note(report : CrawlReport) : String?
      return "Failed, so this run failed. Nothing was seeded from the ranking." if report.failed?

      if (count = report.failed) > 0
        return "#{count} #{count == 1 ? "thing" : "things"} the ranking turned up could not be recorded, so this run failed."
      end

      case report.stop_reason
      when CrawlState::StopReason::COMPLETED_RANK_CAPPED
        "Walked every page both seeds will return, which is their top #{HighValueCrawler::RESULT_CAP} and not the host. " \
        "The cursor is cleared, so the next run starts the ranking again and picks up whatever has since climbed into it."
      when CrawlState::StopReason::INTERRUPTED
        "Stopped at this run's page budget, cursor saved. The next run continues down the ranking."
      when CrawlState::StopReason::RATE_LIMITED
        "Paused by GitHub's rate limit, cursor saved. The next run continues down the ranking."
      when CrawlState::StopReason::TOKEN_MISSING
        "Refused to start without GitHub's token, so nothing was seeded."
      end
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
