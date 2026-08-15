require "./registrar"
require "./discovered_repository"
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
  # credential. The registry has been computing these slugs on every index pass
  # in order to look up a row, finding nothing, and throwing the slug away.
  #
  # WHAT IT COSTS.
  #
  # Nothing. Not one HTTP request, to any host. The candidates are a query over
  # rows this database already holds, and registering one is an insert. That is
  # why this phase cannot be rate limited, cannot be throttled into a partial
  # state, and cannot take budget from the crawl or the indexer it runs beside.
  #
  # It is bounded anyway, and the bound is not about requests. A registered
  # shard has identity and no content until IndexSweep reaches it, so harvesting
  # three thousand leads in one run would put three thousand empty pages in the
  # listing and leave them there for a week. The bound keeps what this phase
  # adds inside what indexing clears, so a lead becomes a page rather than a
  # placeholder.
  #
  # WHAT IT DELIBERATELY DOES NOT DO.
  #
  # It does not verify the repository before registering it, and that is the
  # same contract every other discovery path here has: discovery writes identity
  # and stops, `indexed_at` nil means "not looked at yet", and the shard page
  # renders exactly that. IndexSweep is the verifier, it already fetches this
  # repository on its next pass, and it already records `Unavailable` against a
  # repository that is gone. Checking here would duplicate that fetch, spend the
  # core budget this phase is valuable for not spending, and answer a question
  # that gets asked again twenty minutes later regardless.
  module DependencySweep
    MAX_CANDIDATES_VARIABLE = "DEPENDENCY_MAX_CANDIDATES"

    # Leads harvested per run when DEPENDENCY_MAX_CANDIDATES is unset.
    #
    # Sized against indexing, not against a rate limit. IndexSweep takes 300
    # shards a run and the never-indexed sort first, so a run that harvests
    # fewer than 300 leads hands the next run a backlog it can clear rather than
    # one that grows. 200 leaves room for the re-index traffic that shares that
    # 300, which is what keeps a lead's time-to-content at a run or two instead
    # of drifting out indefinitely as the queue lengthens.
    #
    # The backlog is not lost by being bounded. Unregistered slugs stay in the
    # dependency table and the next run takes the next 200, most-depended-upon
    # first, so the bound sets the rate and never the reach.
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
      getter already_present = 0
      getter skipped = 0
      getter failed = 0
      getter unsupported : Hash(String, Int32)
      getter failures = [] of String
      getter options : Options
      getter remaining : Int64

      def initialize(
        @options : Options,
        @remaining : Int64 = 0_i64,
        @unsupported : Hash(String, Int32) = {} of String => Int32,
      )
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
      # this is a shard and the write path disagreed. A host we do not support
      # is not, and neither is an empty backlog.
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
        io << ", already present " << already_present if already_present > 0
        io << ", skipped " << skipped if skipped > 0
        io << ", failed " << failed if failed > 0
      end
    end

    def self.run(options : Options) : Report
      leads = due(options.max_candidates)
      report = Report.new(options, remaining: outstanding, unsupported: unsupported_hosts)

      Log.info { "Harvesting #{leads.size} repositories named by dependencies, bounded to #{options.max_candidates} this run" }

      leads.each { |lead| harvest(lead, report) }

      report
    end

    private def self.harvest(lead : Lead, report : Report) : Nil
      identity = ShardIdentity.parse_url("https://#{lead.slug}")

      unless identity
        # A slug that will not parse back into an identity cannot have been
        # written by `resolve`, which builds it through the same module. Counted
        # rather than dropped, because a row that got here another way is worth
        # seeing.
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

      # The dependency key is the name, and it is the right one. It is what the
      # shards tool resolves this dependency by, and it is all that is known
      # before the repository is read. Indexing does not overwrite a name, but
      # any later sighting through Registrar does, so a manifest declaring a
      # different `name:` corrects this on the pass that reads it.
      result = Registrar.register(repository, lead.name, nil)
      report.record(lead, result)

      case result.outcome
      in Registrar::Outcome::Created
        Log.info { "Registered #{lead.slug} from #{lead.references} dependency reference#{"s" unless lead.references == 1}" }
      in Registrar::Outcome::Updated then nil
      in Registrar::Outcome::Skipped then Log.info { "Skipped #{result.detail}" }
      in Registrar::Outcome::Failed  then Log.error { "Failed to register #{result.detail}" }
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
      io.puts "  Cost: no host requests. Leads come from manifests already indexed here."
      io.puts

      if report.attempted.zero?
        io.puts "  Nothing to harvest. Every repository named by a dependency is already in the registry."
      else
        io.puts "  #{report}"
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
        io.puts "Could not register:"
        report.failures.each { |failure| io.puts "  #{failure}" }
      end

      io.puts
      remaining = report.remaining - report.registered
      if remaining <= 0
        io.puts "The dependency graph names no repository the registry is missing."
      else
        io.puts "#{remaining} more repositories are named by dependencies and not yet registered."
      end
    end
  end
end
