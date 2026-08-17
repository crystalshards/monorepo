require "../docs_database"

module CrystalShards
  # Builds documentation for the shards people actually reach for, before
  # anybody asks.
  #
  # Documentation is built on first request, which is right for the long tail:
  # most of the catalogue is never opened, and building all of it would spend
  # hours of compiler time on shards nobody reads. It is wrong for the head.
  # The first reader of the most depended-upon shard in the ecosystem pays
  # minutes of clone-and-compile to look at a page, and that reader is the one
  # most likely to be evaluating whether this site is worth using.
  #
  # So the head is warmed on a schedule and the tail stays lazy.
  #
  # Ranking is `ShardQuery#by_popularity`, unchanged: dependents first, then
  # stars. It is deliberately not downloads or page views, both of which are
  # dead columns in this system, and inventing a third ranking here would mean
  # the warmer and the listing disagreed about what "popular" means.
  module DocsWarming
    SCAN_VARIABLE    = "WARM_SCAN_SHARDS"
    ENQUEUE_VARIABLE = "WARM_MAX_BUILDS"

    # How far down the popularity ranking one run looks. The scan is cheap: one
    # query plus one batched lookup against the docs database, no host traffic.
    DEFAULT_SCAN = 200

    # How many builds one run commissions. This is the expensive number: every
    # one is a clone and a compile on the build fleet, and the fleet is shared
    # with the builds readers are waiting on right now. A warm build must never
    # make a reader's own request queue behind it, so the bound is small and
    # the schedule is what provides the throughput.
    DEFAULT_ENQUEUE = 25

    class ConfigurationError < Exception
    end

    record Options, scan : Int32, enqueue : Int32 do
      def self.from_env : Options
        new(
          scan: positive(ENV[SCAN_VARIABLE]?, SCAN_VARIABLE, DEFAULT_SCAN),
          enqueue: positive(ENV[ENQUEUE_VARIABLE]?, ENQUEUE_VARIABLE, DEFAULT_ENQUEUE)
        )
      end

      private def self.positive(raw : String?, variable : String, fallback : Int32) : Int32
        return fallback unless value = raw.presence

        number = value.to_i?
        unless number && number > 0
          raise ConfigurationError.new(
            "#{variable} must be a positive whole number, got #{value.inspect}. " \
            "It bounds one run; the schedule is what provides throughput."
          )
        end

        number
      end
    end

    record Candidate, package_name : String, version : String

    record Failure, candidate : Candidate, reason : String

    record Report,
      scanned : Int32,
      already_documented : Int32,
      in_flight : Int32,
      no_version : Int32,
      enqueued : Array(Candidate),
      failures : Array(Failure),
      options : Options do
      # An enqueue that raised fails the run.
      #
      # The first live execution of this Job printed nineteen packages under
      # "Commissioned:", raised CloudTasksConfig::Missing on every one of them,
      # and exited 0. A misconfigured warmer that reports success is worse than
      # one that does nothing: nothing is at least visible in the docs that
      # never appear, while a green Job with a confident list is a thing an
      # operator stops looking at.
      def exit_code : Int32
        failures.empty? ? 0 : 1
      end
    end

    # Versions this site already has, or is already working on.
    #
    # Both halves matter and they are different facts. A version with a
    # successful build needs nothing. A version with a request row that is
    # pending or building is already on the queue, very possibly because a
    # reader asked for it a moment ago, and enqueueing it again would spend a
    # second clone and compile to produce the identical artifact.
    #
    # Failed builds are deliberately NOT excluded here. crystaldocs owns the
    # retry floor and applies it when a reader asks; a warm run that skipped
    # every past failure forever would never retry a shard that failed once
    # because of a transient network error.
    SETTLED_SQL = <<-SQL
      SELECT docs.package_name, doc_versions.version
      FROM doc_versions
      JOIN docs ON docs.id = doc_versions.doc_id
      WHERE doc_versions.build_status = 'success'
        AND docs.package_name = ANY($1)
      SQL

    IN_FLIGHT_SQL = <<-SQL
      SELECT package_name, version
      FROM doc_build_requests
      WHERE status IN ('pending', 'building')
        AND package_name = ANY($1)
      SQL

    def self.run(options : Options) : Report
      candidates = [] of Candidate
      no_version = 0

      shards = ShardQuery.new.by_popularity.preload_shard_versions.limit(options.scan).results

      shards.each do |shard|
        latest = VersionOrder.latest_version(shard.shard_versions)

        # A shard the indexer has registered but never read a tag from. There
        # is nothing to build, and that is a gap in indexing rather than in
        # documentation, so it is counted and not treated as an error.
        unless latest
          no_version += 1
          next
        end

        candidates << Candidate.new(package_key(shard), latest.version)
      end

      documented = held(SETTLED_SQL, candidates)
      building = held(IN_FLIGHT_SQL, candidates)

      already_documented = 0
      in_flight = 0
      enqueued = [] of Candidate
      failures = [] of Failure

      candidates.each do |candidate|
        key = {candidate.package_name, candidate.version}

        if documented.includes?(key)
          already_documented += 1
          next
        end

        if building.includes?(key)
          in_flight += 1
          next
        end

        break if enqueued.size >= options.enqueue

        # Counted as commissioned only once the queue has actually taken it.
        # A raise here is a misconfigured Job, not a bad shard: the same call
        # is about to fail for every remaining candidate. It is recorded per
        # candidate rather than aborting so the summary states the true scale
        # of the failure instead of the first instance of it.
        begin
          BuildDocsWorker.enqueue(candidate.package_name, candidate.version)
          enqueued << candidate
        rescue ex : Exception
          reason = ex.message.presence || ex.class.name

          Log.error(exception: ex) do
            "DocsWarming: could not commission #{candidate.package_name}@#{candidate.version}"
          end

          failures << Failure.new(candidate, reason)
        end
      end

      Report.new(
        scanned: shards.size,
        already_documented: already_documented,
        in_flight: in_flight,
        no_version: no_version,
        enqueued: enqueued,
        failures: failures,
        options: options
      )
    end

    # The key crystaldocs documents a package under, which is the canonical
    # slug wherever there is one. Matching `RegistryMetadata`'s COALESCE on the
    # other side of the boundary: a bare name is only the key for rows that
    # predate host-qualified identity.
    private def self.package_key(shard : Shard) : String
      shard.canonical_slug || shard.name
    end

    private def self.held(sql : String, candidates : Array(Candidate)) : Set(Tuple(String, String))
      held = Set(Tuple(String, String)).new
      return held if candidates.empty?

      names = candidates.map(&.package_name).uniq!

      DocsDatabase.query_all(sql, names, as: {String, String}).each do |(package_name, version)|
        held << {package_name, version}
      end

      held
    end

    def self.render(report : Report, io : IO = STDOUT) : Nil
      io.puts "Documentation warming"
      io.puts "  Ranking: dependents first, then stars, the same order the listing sorts by."
      io.puts "  Bounds: scanned the top #{report.options.scan}, commissioning at most #{report.options.enqueue} builds."
      io.puts

      if report.enqueued.empty?
        io.puts "Commissioned: nothing."
      else
        io.puts "Commissioned:"
        report.enqueued.each { |candidate| io.puts "  #{candidate.package_name} #{candidate.version}" }
      end

      unless report.failures.empty?
        io.puts
        io.puts "Refused by the queue:"
        report.failures.each do |failure|
          io.puts "  #{failure.candidate.package_name} #{failure.candidate.version}: #{failure.reason}"
        end
      end

      io.puts
      io.puts "Looked at #{report.scanned} shards: " \
              "#{report.already_documented} already documented, " \
              "#{report.in_flight} already building, " \
              "#{report.no_version} with no published version, " \
              "#{report.enqueued.size} commissioned, " \
              "#{report.failures.size} refused."

      # Said plainly, because "commissioned nothing" is the steady state once
      # the head is warm and reads exactly like a broken job otherwise.
      if report.enqueued.empty? && report.failures.empty? && report.already_documented > 0
        io.puts "Nothing to do is the expected result here: the head of the ranking is already built."
      end

      if report.failures.empty?
        io.puts "Exit 0."
      else
        # Named as configuration rather than left as a count, because every
        # candidate failing the same way is what a missing environment variable
        # looks like from here, and that is not something a retry fixes.
        io.puts "Exit #{report.exit_code}. Nothing was commissioned for the refused entries; " \
                "an identical reason on every one of them is a misconfigured Job, not a bad shard."
      end
    end
  end
end
