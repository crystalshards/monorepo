require "./shard_indexer"

# One bounded pass of indexing over the shards discovery has already found.
#
# HOW INDEXING IS TRIGGERED, and why this way.
#
# The discover-shards Cloud Run Job runs three phases: it seeds from GitHub's
# star ranking, sweeps for new repositories, then indexes the stalest shards it
# can afford. Nothing needs a human, and nothing waits for a submission.
#
# The alternatives were a second Job and enqueuing from discovery. A second Job
# would need its own schedule, its own terraform and its own token, and would
# then race the first for the same 5000/hour core budget with neither able to
# see what the other had spent. Enqueuing from discovery is worse: a sweep that
# discovers 2000 repositories would enqueue 2000 index jobs at once, which is
# precisely the stampede the bounded crawl was built to avoid, and it would
# never index a shard discovered before the enqueue existed, which is all 217 of
# the ones that are empty today.
#
# One process, three bounded phases, one budget, and every shard reachable
# whether it was discovered this run or six months ago.
#
# HOW A RUN IS BOUNDED AND RESUMED.
#
# The cursor is `shards.index_attempted_at`, on the row. A pass takes the N
# stalest shards by that column, nulls first, so a shard that has never been
# indexed is always ahead of one that has. Each shard is stamped before it is
# fetched, so a pass strictly advances and the next one continues where this one
# stopped. There is no separate cursor that can fall out of step with the rows
# it describes, and no shared position two processes could disagree about.
module IndexSweep
  MAX_SHARDS_VARIABLE = "INDEX_MAX_SHARDS"

  # Shards per run when INDEX_MAX_SHARDS is unset.
  #
  # Sized from the budget the other two phases leave behind. GitHub gives an
  # authenticated token 5000 core requests an hour, and github.com is the only
  # host with a token today.
  #
  # A discovery sweep bounded to 10 pages reads up to 100 shard.yml files a page,
  # so about 1000 core requests, and the high-value seeding pass bounded to 3
  # pages reads up to 300 more. Their search requests are not in this arithmetic
  # and must not be added to it: code search bills the code_search bucket at 10 a
  # minute and repository search bills the search bucket at 30, neither of which
  # is core. So a run leaves on the order of 3700 core requests unspent.
  #
  # Indexing one shard costs three core requests: the repository, its tag list,
  # and one commit to date the version being indexed. shard.yml and README come
  # from the host's raw file endpoint, which is not the API and does not draw on
  # the core pool.
  #
  # 300 shards is 900 core requests, inside that remainder with room for retries
  # and for another host gaining a token. It also clears the 217 currently-empty
  # shards in a single run, and covers all 5696 discoverable repositories in
  # about 19 runs, which at six-hourly is under five days.
  DEFAULT_MAX_SHARDS = 300

  # Reindexing sooner than this spends requests to learn a star count moved by
  # three. Shards that have never been indexed ignore it entirely: they sort
  # first regardless, because their pages are empty.
  DEFAULT_MIN_AGE = 20.hours

  class ConfigurationError < Exception
  end

  record Options, max_shards : Int32, min_age : Time::Span do
    def self.from_env : Options
      parse(ENV[MAX_SHARDS_VARIABLE]?)
    end

    # Split from `from_env` so the parsing rules are testable without a spec
    # mutating the environment out from under every other spec.
    def self.parse(max_shards : String?, min_age : Time::Span = DEFAULT_MIN_AGE) : Options
      new(max_shards: parse_max_shards(max_shards), min_age: min_age)
    end

    private def self.parse_max_shards(raw : String?) : Int32
      value = raw.try(&.strip).presence
      return DEFAULT_MAX_SHARDS unless value

      shards = value.to_i?
      return shards if shards && shards > 0

      # Refused rather than defaulted, for the same reason DISCOVERY_MAX_PAGES
      # is: a typo silently becoming the default is how an operator ends up
      # certain they changed the budget and unable to see any effect.
      raise ConfigurationError.new(
        "#{MAX_SHARDS_VARIABLE} must be a positive whole number of shards, got #{value.inspect}. " \
        "It bounds one run; the next run continues from the stalest shards remaining."
      )
    end
  end

  # What one pass did, in the terms an operator needs: how many pages stopped
  # being empty, and what is left.
  class Report
    getter indexed = 0
    getter unavailable = 0
    getter failed = 0
    getter unsupported = 0
    getter versions = 0
    getter dependencies = 0
    getter failures = [] of String
    getter options : Options

    def initialize(@options : Options)
    end

    def record(result : ShardIndexer::Result) : Nil
      @versions += result.versions
      @dependencies += result.dependencies

      case result.outcome
      in ShardIndexer::Outcome::Indexed     then @indexed += 1
      in ShardIndexer::Outcome::Unavailable then @unavailable += 1
      in ShardIndexer::Outcome::Unsupported
        # Counted separately from failed. A GitLab shard the indexer cannot read
        # yet is not a fault and must not fail the run, but it also must not
        # vanish from the arithmetic: a sweep reporting "attempted 300, indexed
        # 40" with 260 unaccounted for is how a whole host stays empty without
        # anyone noticing.
        @unsupported += 1
      in ShardIndexer::Outcome::Failed
        @failed += 1
        # Capped: a run where everything fails should not produce a summary
        # nobody can read, and the pattern is visible in the first few.
        @failures << "#{result.shard.canonical_slug}: #{result.detail}" if @failures.size < 20
      end
    end

    def attempted : Int32
      indexed + unavailable + failed + unsupported
    end

    # A pass fails when everything it tried failed. One repository being deleted
    # is normal; every repository failing is a bad token or a host outage, and
    # that must not exit 0.
    def ok? : Bool
      attempted.zero? || failed < attempted
    end

    def exit_code : Int32
      ok? ? 0 : 1
    end

    def to_s(io : IO) : Nil
      io << "indexed " << indexed
      io << ", " << versions << " version" << ("s" unless versions == 1)
      io << ", " << dependencies << " dependency edge" << ("s" unless dependencies == 1)
      io << ", unavailable " << unavailable if unavailable > 0
      io << ", unsupported host " << unsupported if unsupported > 0
      io << ", failed " << failed if failed > 0
    end
  end

  # Test seam. Specs replace this to drive the whole sweep without touching a
  # host, and must restore it in an `ensure`.
  class_property indexer : Proc(Shard, ShardIndexer::Result) = ->(shard : Shard) {
    ShardIndexer.index(shard)
  }

  def self.run(options : Options, now : Time = Time.utc) : Report
    report = Report.new(options)
    shards = due(options, now)

    Log.info { "Indexing #{shards.size} shards, bounded to #{options.max_shards} this run" }

    shards.each do |shard|
      begin
        result = @@indexer.call(shard)
      rescue ex : Exception
        # One shard raising must not lose the rest of the pass, nor the summary
        # of the shards already done.
        Log.error(exception: ex) { "Indexing #{shard.canonical_slug} raised" }
        result = ShardIndexer::Result.new(
          ShardIndexer::Outcome::Failed,
          shard,
          detail: ex.message.presence || ex.class.name,
        )
      end

      report.record(result)
      Log.info { "#{shard.canonical_slug}: #{result.outcome}#{result.detail ? " (#{result.detail})" : ""}" }
    end

    report
  end

  # The stalest shards, nulls first. Ordering by the same column that is stamped
  # before each fetch is what makes a pass strictly advance: nothing already
  # touched sorts ahead of something that has not been.
  #
  # `id` breaks ties so the order is total. Without it, the 217 rows that all
  # have a null cursor come back in whatever order Postgres feels like, and two
  # consecutive runs could pick overlapping sets and never reach the tail.
  def self.due(options : Options, now : Time = Time.utc) : Array(Shard)
    ShardQuery.new
      .index_attempted_at.lte(now - options.min_age)
      .or(&.index_attempted_at.is_nil)
      .index_attempted_at.asc_order(:nulls_first)
      .id.asc_order
      .limit(options.max_shards)
      .to_a
  end

  # How much of the registry has content, so nobody has to infer progress from
  # one run's counts.
  def self.coverage_summary : String
    total = ShardQuery.new.select_count
    return "Registry is empty: discovery has found nothing to index." if total.zero?

    indexed = ShardQuery.new.indexed_at.is_not_nil.select_count
    never = total - indexed
    percent = (indexed * 100.0 / total).round(1)

    line = "Indexed #{indexed} of #{total} shards (#{percent}%)."
    return line if never.zero?

    "#{line} #{never} still have no content and sort first on the next run."
  end

  def self.render(report : Report, io : IO = STDOUT) : Nil
    io.puts "Shard indexing"
    io.puts "  Bound: #{report.options.max_shards} shards this run, stalest first."
    io.puts "  Cursor: shards.index_attempted_at, stamped per shard before it is fetched."
    io.puts

    if report.attempted.zero?
      io.puts "  Nothing was due. Every shard has been indexed within the last #{report.options.min_age.total_hours.round} hours."
    else
      io.puts "  #{report}"
    end

    unless report.failures.empty?
      io.puts
      io.puts "Could not index:"
      report.failures.each { |failure| io.puts "  #{failure}" }
    end

    io.puts
    io.puts coverage_summary
  end
end
