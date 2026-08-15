require "./registrar"
require "./discovered_repository"
require "../shard_indexer"
require "../git_host_policy"
require "../shard_identity"

module Discovery
  # Discovery from the dependency graph the registry already holds.
  #
  # WHY THIS EXISTS.
  #
  # Every other way this registry finds a shard asks a host to enumerate itself,
  # and each of those enumerations has a ceiling nothing in this codebase can
  # raise. GithubCrawler partitions code search by manifest byte size, which is
  # exhaustive over GitHub's code search INDEX and blind to everything GitHub
  # has not indexed, including every fork. HighValueCrawler reads twenty pages
  # of a star ranking and then starts again. The other three hosts are skipped
  # entirely until somebody issues a token. When github.com reported
  # `completed_exhaustive`, the registry stopped growing at roughly one new
  # shard a run, and that was not the crawl falling behind: it was the crawl
  # having read everything its one source will admit.
  #
  # A dependency edge is a different kind of evidence, and a better one. Code
  # search says "a file called shard.yml exists at this root". A manifest saying
  #
  #   radix:
  #     github: luislavena/radix
  #
  # says another shard, already indexed here, depends on that repository. It
  # names the host, the owner and the repository exactly, it is published by
  # someone with a reason to get it right, and it is true of forks, of
  # repositories GitHub never indexed, and of the three hosts with no
  # credential.
  #
  # HOW A LEAD BECOMES A PAGE.
  #
  # Resolve locally, and when that finds nothing, go and read the repository.
  #
  # UpdateDependenciesWorker does the first half on every index pass: it turns a
  # declared source into a canonical slug and looks for a row. What it cannot do
  # is the second half. It runs inside a transaction holding the version row FOR
  # UPDATE, so a host read there would pin a locked row and a pooled connection
  # across network latency, once per dependency; and it is reached from
  # ShardIndexRequests, which indexes inline in a reader's page load under a
  # twenty second bound, where fanning out into N repository fetches would spend
  # that budget on somebody's page view. So the resolver records which
  # repository the dependency named, in `dependencies.resolved_slug`, and this
  # phase is the second half: bounded, outside any transaction, and nowhere near
  # a request.
  #
  # Each lead is registered and then read in the same pass, through the same
  # ShardIndexer every other shard goes through. That is the difference between
  # a lead and a page. Registering alone would leave a row carrying an identity,
  # the dependency key for a name and nothing else, waiting a full index cycle
  # for content, and it would leave that row standing whether or not the
  # repository turned out to exist. Reading it now means the row lands with the
  # manifest's own name, its stars, its versions and its README, and a lead
  # naming a repository that has been deleted or renamed is marked unavailable
  # in the run that found it rather than looking live until something checks.
  #
  # WHAT IT COSTS.
  #
  # Finding the leads costs nothing: they are a query over rows this database
  # already holds, so no search API, no code search bucket, nothing to throttle.
  # Reading one costs what indexing any shard costs, three core requests, and
  # the bound is sized against what the phases before it leave unspent.
  #
  # WHERE IT SITS.
  #
  # Last, after indexing, and the order earns its place twice. Its leads come
  # from manifests indexing has stored, so running after it harvests the
  # manifests this run just read rather than the previous run's. And it spends
  # what is left of the budget rather than competing for it: a run throttled
  # earlier reaches this phase with less to spend and registers fewer, which is
  # the failure mode worth having.
  module DependencySweep
    MAX_CANDIDATES_VARIABLE = "DEPENDENCY_MAX_CANDIDATES"

    # Leads read per run when DEPENDENCY_MAX_CANDIDATES is unset.
    #
    # Sized from the budget the three phases before this one leave behind.
    # GitHub gives an authenticated token 5000 core requests an hour. A 10 page
    # sweep spends about 1000 of them, the 3 page seed about 300, and indexing
    # 300 shards about 900, so roughly 2800 remain. Reading one lead is the same
    # three core requests indexing any shard costs, so 200 leads is about 600:
    # comfortably inside the remainder, with room for retries and for another
    # host gaining a credential.
    #
    # Not sized against INDEX_MAX_SHARDS, which is what bounded this phase when
    # it registered leads without reading them. A registered-but-blank row had
    # to wait for the indexing phase to reach it, so harvesting faster than that
    # phase cleared filled the listing with pages that had nothing on them. A
    # lead that is read on arrival pays its own way: it lands indexed, and
    # IndexSweep does not pick it up again any sooner than it would any other
    # freshly indexed shard.
    #
    # Leads are never lost to the bound. An unregistered slug stays in the
    # dependency table and the next run takes the next batch, most depended-upon
    # first, so this sets the rate and never the reach.
    DEFAULT_MAX_CANDIDATES = 200

    class ConfigurationError < Exception
    end

    record Options, max_candidates : Int32 do
      def self.from_env : Options
        parse(ENV[MAX_CANDIDATES_VARIABLE]?)
      end

      # Split from `from_env` so the parsing rules are testable without a spec
      # mutating the environment out from under every other spec.
      def self.parse(max_candidates : String?) : Options
        value = max_candidates.try(&.strip).presence
        return new(max_candidates: DEFAULT_MAX_CANDIDATES) unless value

        count = value.to_i?
        return new(max_candidates: count) if count && count > 0

        # Refused rather than defaulted, matching DISCOVERY_MAX_PAGES and
        # INDEX_MAX_SHARDS. A typo silently becoming the default is how an
        # operator ends up certain they changed the budget and unable to see
        # any effect.
        raise ConfigurationError.new(
          "#{MAX_CANDIDATES_VARIABLE} must be a positive whole number of repositories, got #{value.inspect}. " \
          "It bounds one run; unharvested leads stay in the dependency table and the next run takes the next batch."
        )
      end
    end

    # One repository named by a dependency and absent from the registry.
    #
    # `references` is how many dependency rows name it, which is the ordering
    # signal: the most depended-upon missing shard is the one whose absence
    # costs the most pages a correct dependents count.
    record Lead, slug : String, name : String, references : Int64

    # What one pass did.
    #
    # The counts separate the two halves deliberately. `registered` is how many
    # rows this run created and `indexed` how many of those came back with
    # content, so a gap between them is the interesting number: leads the graph
    # named that the host would not give us, which is a fact about the ecosystem
    # rather than a fault in the run.
    #
    # `unsupported` is a census of the whole graph rather than a tally of this
    # run, and it has to be. A lead on a host the registry cannot store can
    # never be registered, so it never leaves the candidate set: counted inside
    # the bound it would take a slot from a registrable lead on every run for
    # the rest of time, and sort ahead of one whenever its name did. They are
    # excluded from the candidate query for that reason, which leaves nothing
    # for a per-run tally to count.
    #
    # Broken out by host because the number is actionable. Every entry is a
    # repository the ecosystem demonstrably depends on and this registry cannot
    # hold, so the breakdown is the answer to "what would supporting this host
    # actually buy". Left as one number it reads as noise.
    class Report
      getter registered = 0
      getter indexed = 0
      getter unavailable = 0
      getter index_failed = 0
      getter versions = 0
      getter already_present = 0
      getter skipped = 0
      getter failed = 0
      getter failures = [] of String
      getter options : Options

      # Both measured after the loop rather than before it. Reading a lead's
      # manifest can name repositories that were not leads when the run started,
      # so a backlog sampled up front is a number that was already wrong by the
      # time it was printed.
      property remaining : Int64 = 0_i64
      property unsupported : Hash(String, Int32) = {} of String => Int32

      def initialize(@options : Options)
      end

      def record(lead : Lead, result : Registrar::Result) : Nil
        case result.outcome
        in Registrar::Outcome::Created then @registered += 1
        in Registrar::Outcome::Updated
          # The anti-join should have excluded this: a slug with a row is not a
          # lead. Reaching it means a row appeared between the query and the
          # write, which is benign and worth counting rather than folding into
          # `registered`, where it would overstate what this run found.
          @already_present += 1
        in Registrar::Outcome::Skipped
          @skipped += 1
          @failures << "#{lead.slug}: #{result.detail}" if @failures.size < 20
        in Registrar::Outcome::Failed
          @failed += 1
          @failures << "#{lead.slug}: #{result.detail}" if @failures.size < 20
        end
      end

      # The outcome of reading a lead's repository, which is ShardIndexer's
      # verdict unchanged. Recorded rather than reduced to success or failure,
      # because "the graph named a repository that is gone" and "the host would
      # not answer just now" are different facts and only the second is worth
      # trying again.
      def record_index(lead : Lead, result : ShardIndexer::Result) : Nil
        @versions += result.versions

        case result.outcome
        in ShardIndexer::Outcome::Indexed     then @indexed += 1
        in ShardIndexer::Outcome::Unavailable then @unavailable += 1
        in ShardIndexer::Outcome::Unsupported
          # Not reachable from here: `due` filters to hosts the registry stores,
          # which is the same list RepositorySourceFactory reads. Counted with
          # the read failures rather than dropped, so if those two lists ever
          # diverge the number says so instead of vanishing.
          @index_failed += 1
          @failures << "#{lead.slug}: #{result.detail}" if @failures.size < 20
        in ShardIndexer::Outcome::Failed
          @index_failed += 1
          @failures << "#{lead.slug}: #{result.detail}" if @failures.size < 20
        end
      end

      def unsupported_count : Int32
        @unsupported.values.sum
      end

      # What this run touched. Deliberately excludes `unsupported`, which is a
      # standing census of leads the phase never attempts: folding it in would
      # make a run that harvested nothing report itself as having done work, and
      # would grow the number every time a new unreachable host appeared.
      def attempted : Int32
        registered + already_present + skipped + failed
      end

      # A lead the registry refused to store is a real problem: the graph said
      # this is a shard and the write path disagreed.
      #
      # A lead the HOST would not give us is not, and does not fail the run. A
      # repository named by a manifest and since deleted is an ordinary fact
      # about an ecosystem, the row records it, and failing the Job over one
      # would put a red mark on nearly every run forever.
      def ok? : Bool
        failed.zero?
      end

      def exit_code : Int32
        ok? ? 0 : 1
      end

      # The run, and only the run. The unsupported census gets its own section
      # in `render`, where there is room to name the hosts.
      def to_s(io : IO) : Nil
        io << "registered " << registered << " from the dependency graph"
        io << ", indexed " << indexed
        io << ", " << versions << " version" << ("s" unless versions == 1)
        io << ", gone " << unavailable if unavailable > 0
        io << ", could not read " << index_failed if index_failed > 0
        io << ", already present " << already_present if already_present > 0
        io << ", skipped " << skipped if skipped > 0
        io << ", refused " << failed if failed > 0
      end
    end

    # Test seam. The per-lead read goes through this proc, which defaults to the
    # real indexer. Specs replace it to drive the whole phase without touching a
    # host, and must restore it in an `ensure`. Deliberately the same shape as
    # IndexSweep.indexer: this is the same work reached from a different queue,
    # and a second way of faking it would be a second thing to keep in step.
    class_property indexer : Proc(Shard, ShardIndexer::Result) = ->(shard : Shard) {
      ShardIndexer.index(shard)
    }

    def self.run(options : Options) : Report
      leads = due(options.max_candidates)
      report = Report.new(options)

      Log.info { "Harvesting #{leads.size} repositories named by dependencies, bounded to #{options.max_candidates} this run" }

      leads.each { |lead| harvest(lead, report) }

      report.remaining = outstanding
      report.unsupported = unsupported_hosts
      report
    end

    private def self.harvest(lead : Lead, report : Report) : Nil
      identity = ShardIdentity.parse_url("https://#{lead.slug}")

      unless identity
        # A slug that will not parse back into an identity cannot have been
        # written by the resolver, which builds it through the same module.
        # Counted rather than dropped, because a row that got here another way
        # is worth seeing.
        report.record(lead, Registrar::Result.new(
          Registrar::Outcome::Skipped,
          detail: "#{lead.slug} is not an identity the registry can address"
        ))
        return
      end

      # Belt and braces. `due` filters the host in SQL, so reaching this means a
      # resolved_slug got past the allowlist some other way. Compared against
      # the allowlist directly and not through `safe_fetch_url?`, which resolves
      # DNS: this asks which hosts we support, and that question has no network
      # in it.
      unless GitHostPolicy::ALLOWED_HOSTS.includes?(identity.host)
        report.record(lead, Registrar::Result.new(
          Registrar::Outcome::Skipped,
          detail: "#{lead.slug} is on #{identity.host}, which the registry does not store"
        ))
        return
      end

      repository = DiscoveredRepository.new(
        host: identity.host,
        owner: identity.owner,
        repo: identity.repo,
        repository_url: "https://#{identity.canonical_slug}",
      )

      # The dependency key is the name the row is created with, and it is the
      # right one to start from: it is what the shards tool resolves this
      # dependency by, and it is the only name anybody has before the repository
      # is read. The read that follows replaces the rest of the row with the
      # repository's own facts.
      result = Registrar.register(repository, lead.name, nil)
      report.record(lead, result)

      case result.outcome
      in Registrar::Outcome::Created
        # The row exists and is empty. Reading it is what makes it a page.
        if shard = result.shard
          read(lead, shard, report)
        end
      in Registrar::Outcome::Updated then nil
      in Registrar::Outcome::Skipped then Log.info { "Skipped #{result.detail}" }
      in Registrar::Outcome::Failed  then Log.error { "Failed to register #{result.detail}" }
      end
    end

    # Reads the repository a lead named, through the same indexer every other
    # shard goes through.
    #
    # One lead raising must not lose the rest of the batch, nor the rows already
    # written, which is the same rescue IndexSweep keeps around its own per
    # shard call and for the same reason.
    private def self.read(lead : Lead, shard : Shard, report : Report) : Nil
      result = begin
        @@indexer.call(shard)
      rescue ex : Exception
        Log.error(exception: ex) { "Reading #{lead.slug} raised" }
        ShardIndexer::Result.new(
          ShardIndexer::Outcome::Failed,
          shard,
          detail: ex.message.presence || ex.class.name,
        )
      end

      report.record_index(lead, result)

      Log.info do
        "Registered #{lead.slug} from #{lead.references} dependency reference#{"s" unless lead.references == 1}: " \
        "#{result.outcome}#{result.detail ? " (#{result.detail})" : ""}"
      end
    end

    # The leads for one run: repositories named by a dependency, absent from the
    # registry, on a host it can store, most-referenced first.
    #
    # Raw SQL because this is an anti-join and an aggregate, which the query
    # builder does not express, and because the ordering matters more than the
    # convenience would.
    #
    # `dependent_shard_id IS NULL` is the recorded belief that this slug had no
    # row when the edge was last resolved, and it is what the partial index
    # covers. The join against `shards` is what makes that belief current: a
    # slug registered by an earlier run keeps its stale NULL until the version
    # naming it is reindexed, and without the join those slugs would fill the
    # bound with work already done.
    #
    # The host filter is load-bearing rather than tidy. A lead on a host the
    # registry cannot store can never be registered, so it never stops being a
    # lead: left in, it would take a slot out of every run's bound forever, and
    # take it ahead of a registrable lead whenever the ordering favoured it.
    # Filtering in SQL is what keeps the bound spent entirely on work that can
    # finish. The count of what was excluded is not lost, it is reported by
    # `unsupported_hosts` across the whole graph instead of one run's slice.
    #
    # MIN(name) rather than any name, so the order and the chosen name are both
    # deterministic. Manifests do occasionally disagree about what to call the
    # same repository, and a run picking a different one each time would rewrite
    # the row's name on every pass.
    #
    # The slug tiebreak makes the order total. Without it two runs can return
    # overlapping prefixes of the same reference count and never reach the tail,
    # which is the same reasoning that put `id` at the end of IndexSweep's order.
    def self.due(limit : Int32) : Array(Lead)
      AppDatabase.query_all(
        <<-SQL,
        SELECT d.resolved_slug, MIN(d.name), COUNT(*)
        FROM dependencies d
        LEFT JOIN shards s ON s.canonical_slug = d.resolved_slug
        WHERE d.resolved_slug IS NOT NULL
          AND d.dependent_shard_id IS NULL
          AND s.id IS NULL
          AND split_part(d.resolved_slug, '/', 1) = ANY($1)
        GROUP BY d.resolved_slug
        ORDER BY COUNT(*) DESC, d.resolved_slug ASC
        LIMIT $2
        SQL
        GitHostPolicy::ALLOWED_HOSTS, limit, as: {String, String, Int64}
      ).map { |slug, name, references| Lead.new(slug: slug, name: name, references: references) }
    end

    # Repositories the dependency graph names on hosts the registry cannot
    # store, by host.
    #
    # A census, not a run's tally, because these are excluded from the candidate
    # set: nothing this phase does will ever change the number, so counting only
    # the ones a bound happened to reach would report a different figure every
    # run for a quantity that had not moved.
    def self.unsupported_hosts : Hash(String, Int32)
      rows = AppDatabase.query_all(
        <<-SQL,
        SELECT split_part(d.resolved_slug, '/', 1) AS host, COUNT(DISTINCT d.resolved_slug)
        FROM dependencies d
        LEFT JOIN shards s ON s.canonical_slug = d.resolved_slug
        WHERE d.resolved_slug IS NOT NULL
          AND d.dependent_shard_id IS NULL
          AND s.id IS NULL
          AND NOT (split_part(d.resolved_slug, '/', 1) = ANY($1))
        GROUP BY 1
        SQL
        GitHostPolicy::ALLOWED_HOSTS, as: {String, Int64}
      )

      rows.to_h { |host, count| {host, count.to_i} }
    end

    # How many distinct repositories the dependency graph names, the registry
    # does not have, and this phase can actually register. The number it exists
    # to drive to zero.
    #
    # Scoped to registrable leads for exactly that reason: counting the
    # unsupported hosts here would make it a number that never reaches zero and
    # so never means anything. Those are reported separately and as a census,
    # because they are a coverage boundary rather than a backlog.
    def self.outstanding : Int64
      AppDatabase.query_one(
        <<-SQL,
        SELECT COUNT(DISTINCT d.resolved_slug)
        FROM dependencies d
        LEFT JOIN shards s ON s.canonical_slug = d.resolved_slug
        WHERE d.resolved_slug IS NOT NULL
          AND d.dependent_shard_id IS NULL
          AND s.id IS NULL
          AND split_part(d.resolved_slug, '/', 1) = ANY($1)
        SQL
        GitHostPolicy::ALLOWED_HOSTS, as: Int64
      )
    end

    def self.render(report : Report, io : IO = STDOUT) : Nil
      io.puts "Dependency graph harvest"
      io.puts "  Bound: #{report.options.max_candidates} repositories this run, most depended-upon first."
      io.puts "  Leads: manifests already indexed here, so finding them costs no host requests."
      io.puts "  Each one is then read through the same indexer every other shard goes through."
      io.puts

      if report.attempted.zero?
        io.puts "  Nothing to harvest. Every repository named by a dependency is already in the registry."
      else
        io.puts "  #{report}"
      end

      if report.unavailable > 0
        io.puts
        io.puts "  #{report.unavailable} named a repository the host no longer serves. The rows stay and say so:"
        io.puts "  a manifest outlives a rename, and other shards still depend on the name it used."
      end

      unless report.unsupported.empty?
        io.puts
        io.puts "Named by a dependency, on a host the registry cannot store:"
        report.unsupported.to_a.sort_by { |host, count| {-count, host} }.each do |host, count|
          io.puts "  #{host}: #{count} repositor#{count == 1 ? "y" : "ies"}"
        end
      end

      unless report.failures.empty?
        io.puts
        io.puts "Could not register or read:"
        report.failures.each { |failure| io.puts "  #{failure}" }
      end

      io.puts
      if report.remaining <= 0
        io.puts "The dependency graph names no repository the registry is missing."
      else
        io.puts "#{report.remaining} more repositories are named by dependencies and not yet registered."
      end
    end
  end
end
