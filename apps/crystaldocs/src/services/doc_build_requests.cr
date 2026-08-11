module CrystalDocs
  # Registers a (package, version) combination for documentation building and
  # puts it on the queue at most once.
  #
  # Documentation is built on first request, the way ruby-doc.info does it,
  # rather than eagerly for every published version of every shard. The
  # request path therefore has to be able to say "no artifact yet" without
  # either building inline or re-queueing on every page view.
  #
  # Building inline is not an option worth discussing: a build clones a
  # repository and compiles third party code in a sandbox. Doing that inside
  # the HTTP request holds the connection for minutes and hands any visitor a
  # trivial denial of service by requesting a few dozen cold versions. This
  # service only ever enqueues.
  #
  # Every decision about whether to enqueue is made by the database, not by
  # this process. `INSERT ... ON CONFLICT DO NOTHING RETURNING id` and a
  # conditional `UPDATE ... RETURNING id` each return a row only to the caller
  # that actually changed something, so "did I win the right to enqueue?" and
  # "is the row now in the state I think it is?" are the same question with
  # the same answer. Read-then-write in application code gets this wrong under
  # exactly the concurrency that matters: several readers landing on the same
  # cold version at once.
  class DocBuildRequests
    # How long a failed build is left alone before anyone may ask for it
    # again.
    #
    # Without a floor, every visitor to a package that cannot build re-queues
    # it, so one permanently broken shard with a little traffic saturates the
    # build queue and starves shards that would succeed. An hour is long
    # enough that a transient failure (a registry blip, a timeout, a full
    # disk) has cleared on its own, and short enough that a real fix published
    # by a maintainer is picked up the same day. The floor is measured from
    # failed_at, which the builder writes, not from the time of the request,
    # so a stream of readers cannot walk it forward.
    RETRY_FLOOR = 1.hour

    # The identity of a build is (package, version) and deliberately NOT
    # (package, version, crystal version).
    #
    # That is only correct while every artifact is produced by one canonical
    # compiler, which is the case today: the sandbox pins a single image and
    # storage holds one docs.json per version. If we ever build the same shard
    # release against several compilers, this key becomes wrong rather than
    # merely incomplete: the second compiler's request would dedupe onto the
    # first one's row and the reader would be served documentation built by a
    # compiler they did not ask for.
    #
    # So extending to a matrix means extending this uniqueness key and the
    # artifact path together. Scoped on purpose, not overlooked.
    CANONICAL_COMPILER_ONLY = true

    # Claims a brand new combination. Returns the row id only to the caller
    # whose INSERT actually created it; concurrent callers get nil.
    CLAIM_NEW_SQL = <<-SQL
      INSERT INTO doc_build_requests
        (package_name, version, status, requested_at, attempts, created_at, updated_at)
      VALUES ($1, $2, 'pending', $3, 1, $3, $3)
      ON CONFLICT (package_name, version) DO NOTHING
      RETURNING id
      SQL

    # Puts a failed build back on the queue once the floor has passed, and
    # only for the one caller whose UPDATE matched. The status predicate is
    # part of the WHERE clause rather than a check performed beforehand, so
    # two readers arriving a millisecond apart cannot both queue a retry.
    #
    # Deliberately not retryable here: succeeded. An already built version
    # enqueues nothing, and a succeeded row whose artifact has gone missing is
    # an inconsistency to surface, not a rebuild to trigger silently.
    #
    # PRECONDITION, and it will not hold forever. This is only correct while
    # artifacts are never removed. The planned storage model evicts artifacts
    # that have not been read for a long time and regenerates them on the next
    # request, and under that model "succeeded, artifact absent" is the normal
    # steady state rather than a fault. Shipping eviction against this rule
    # would make every evicted package permanently unavailable: the row says
    # succeeded, so nothing ever rebuilds it, and storage has nothing to serve.
    #
    # So eviction must land together with a succeeded-and-missing reclaim, and
    # a test that a request after eviction rebuilds rather than dead-ends.
    CLAIM_RETRY_SQL = <<-SQL
      UPDATE doc_build_requests
      SET status = 'pending',
          requested_at = $3,
          attempts = attempts + 1,
          started_at = NULL,
          finished_at = NULL,
          failed_at = NULL,
          last_error = NULL,
          updated_at = $3
      WHERE package_name = $1
        AND version = $2
        AND status = 'failed'
        AND failed_at IS NOT NULL
        AND failed_at <= $4
      RETURNING id
      SQL

    RECORD_JOB_SQL = <<-SQL
      UPDATE doc_build_requests
      SET job_id = $2, updated_at = $3
      WHERE id = $1
      SQL

    def initialize(@queue : DocsBuildQueue = DocsBuildQueue.build)
    end

    # Ask for documentation for this combination.
    #
    # Safe to call on every cache miss and on every page view: it enqueues a
    # build only when the database says this caller is the one that changed
    # the row. Returns the current request so the caller can tell the reader
    # whether to wait or that the build failed.
    def request(package_name : String, version : String) : DocBuildRequest
      now = Time.utc

      if id = claim_new(package_name, version, now)
        enqueue(id, package_name, version, now)
      elsif id = claim_retry(package_name, version, now)
        enqueue(id, package_name, version, now)
      end

      # Read back rather than returning something assembled here: the builder
      # writes to this row too, and it may have moved on already.
      find(package_name, version) || raise "doc_build_requests row for #{package_name} #{version} disappeared immediately after being claimed."
    end

    def find(package_name : String, version : String) : DocBuildRequest?
      DocBuildRequestQuery.new
        .package_name(package_name)
        .version(version)
        .first?
    end

    private def claim_new(package_name : String, version : String, now : Time) : Int64?
      AppDatabase.query_all(
        CLAIM_NEW_SQL,
        package_name,
        version,
        now,
        as: Int64
      ).first?
    end

    private def claim_retry(package_name : String, version : String, now : Time) : Int64?
      AppDatabase.query_all(
        CLAIM_RETRY_SQL,
        package_name,
        version,
        now,
        now - RETRY_FLOOR,
        as: Int64
      ).first?
    end

    # The row is already pending at this point, so a queue that cannot be
    # reached leaves a pending request with no build id rather than a lie. The
    # next reader after the retry floor is not affected, because the floor
    # only governs failed rows; a request stuck pending because Cloud Tasks
    # was unreachable is visible in the data and is not silently retried here.
    private def enqueue(id : Int64, package_name : String, version : String, now : Time) : Nil
      job_id = @queue.enqueue(package_name, version)
      return if job_id.nil?

      AppDatabase.exec(RECORD_JOB_SQL, id, job_id, now)
    end
  end
end
