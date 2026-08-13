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

    # How long a claimed build may show no outcome before anyone may ask for
    # it again.
    #
    # A row only ever left 'pending' or 'building' is a row nothing will ever
    # revisit: the retry path below matches on 'failed', so a request whose
    # task was never delivered, or whose builder died before writing an
    # outcome, stays claimed forever. Every reader after that sees "being
    # built" and no build is happening or ever will.
    #
    # That is not hypothetical. It is what the whole published catalogue
    # looked like after the launcher spent its entire life unable to
    # authenticate: the rows were claimed during the outage, the outage was
    # fixed, and not one of them moved, because nothing reconsiders a claim.
    #
    # Measured from the claim rather than from the request, so a stream of
    # readers cannot walk it forward. It has to exceed the longest a build can
    # legitimately take, or a slow build would be re-queued while it is still
    # running: the sandbox is bounded by DOCS_SANDBOX_TIMEOUT_SECONDS and the
    # launcher holds the request open for the whole build, so this sits beyond
    # both.
    STALE_CLAIM_FLOOR = 1.hour

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
        AND (
          (status = 'failed' AND failed_at IS NOT NULL AND failed_at <= $4)
          OR
          -- A claim nobody ever resolved. Measured from the moment it was
          -- claimed, and only past a floor beyond the longest a build can
          -- legitimately take, so a build still running is never re-queued
          -- underneath itself.
          (status IN ('pending', 'building')
            AND COALESCE(started_at, requested_at) IS NOT NULL
            AND COALESCE(started_at, requested_at) <= $5)
        )
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

    # Ask for documentation for this combination, and for the documentation a
    # reader of it will immediately want to follow a link into: the
    # dependencies this exact release declared, and the standard library for
    # the Crystal it targets.
    #
    # A page whose dependencies are unbuilt is a page whose cross links are
    # plain text. `DependencyIndex` only maps a name to a page when the owning
    # package has a version with a successful build, so a reader on kemal saw
    # `Radix::Tree` as dead text and nothing about reading kemal changed it.
    # Commissioning is where the two get connected, because it is the only
    # moment we know which release of which dependency this reader's page
    # needs.
    #
    # DIRECT DEPENDENCIES ONLY, and never a transitive walk.
    #
    # A reader is waiting on this call. A transitive closure is a graph
    # traversal of unknown depth with a registry round trip per node, on a
    # request whose whole job is to render one page and enqueue at most a
    # handful of builds, and its cost is set by whatever the dependency graph
    # happens to look like rather than by anything the reader did. Direct only
    # costs two statements against the registry, no matter what the graph
    # looks like.
    #
    # What direct only gives up, stated honestly: the closure is not complete
    # after one call. It completes as each dependency is itself commissioned,
    # which happens when a reader opens that dependency's page, or when
    # another package that depends on it is commissioned. Every commissioning
    # widens the built set by one level, and crossing an edge that has already
    # been crossed costs one INSERT that changes nothing.
    #
    # The parent is committed before any of this, and the cascade cannot
    # unmake it. The reader asked for the parent; the dependencies are our
    # inference about what they will want next, and an inference must not be
    # able to fail the thing it was inferred from.
    def request_with_dependencies(package_name : String, version : String) : DocBuildRequest
      requested = request(package_name, version)
      commission_dependencies(package_name, version)
      requested
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
        now - STALE_CLAIM_FLOOR,
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

    # Everything beyond the package the reader named.
    #
    # Termination is the property to be clear about, because the dependency
    # graph has cycles in it and nothing here checks for one. It terminates
    # for two independent reasons, and either alone is sufficient:
    #
    #   * There is no recursion. This commissions direct dependencies with
    #     `request`, which enqueues and returns; it never re-enters itself. A
    #     cycle would have to be traversed by successive calls from outside.
    #   * `request` is idempotent per (package, version). The unique index
    #     makes the INSERT a no-op for a row that exists, and the retry UPDATE
    #     matches only a failed or abandoned row, so a pending, building or
    #     succeeded combination enqueues nothing. Crossing the same edge again
    #     costs one INSERT that changes nothing.
    #
    # So A depending on B depending on A commissions each exactly once,
    # whichever of them a reader arrives at first and however many times they
    # reload.
    #
    # Rescued as a whole, and this is the only rescue on the path. The parent
    # was committed before this ran. A registry that is unreachable, or that
    # breaks mid-statement, must cost the cascade and nothing else, because
    # the parent is what the reader asked for and it is already enqueued.
    private def commission_dependencies(package_name : String, version : String) : Nil
      declaration = RegistryPackages.build.declaration(package_name, version)

      if core = core_version_for(declaration.crystal_requirement)
        request(CORE_PACKAGE, core)
      end

      declaration.dependencies.each do |dependency|
        request(dependency.package_name, dependency.version)
      end
    rescue ex
      Log.warn { "Could not commission the dependencies of #{package_name} #{version}: #{ex.message}" }
    end

    # Which Crystal release to document alongside a package that declared
    # `crystal: <requirement>`, or nil when there is nothing to commission.
    #
    # Nil when we already hold one that satisfies. `DependencyIndex` links
    # core types to the HIGHEST core version with a successful build that
    # satisfies the reader's package requirement, so once any satisfying
    # version exists the reader's links already resolve, and a second build
    # lower down the range would be selected by nothing. Skipping it is not an
    # optimisation, it is refusing to compile an old compiler for a page that
    # would never link to it.
    #
    # Otherwise the floor: the lowest release the declaration admits. That is
    # the only concrete Crystal release the declaration actually names.
    # Choosing anything higher means choosing from the list of Crystal releases
    # that exist, and this app has no such list: the registry indexes shards
    # and crystal-lang/crystal is not one of them, so ">= 1.12.0" resolves to
    # 1.12.0 or to a guess. A floor is also the conservative reading of the
    # declaration, since a type present in the Crystal a shard declares
    # support for is present in every later one.
    #
    # Nil again when the requirement names no floor at all. "*", a bare
    # ceiling like "< 2.0.0" and a strict ">" name no release we could commit
    # to, and the floor is checked against the requirement rather than
    # assumed, so a requirement whose lowest bound it does not itself satisfy
    # commissions nothing rather than a version that cannot be right.
    private def core_version_for(crystal_requirement : String?) : String?
      requirement = Semver::Requirement.parse?(crystal_requirement)
      return nil unless requirement
      return nil if core_already_satisfies?(requirement)

      floor = requirement.clauses
        .select { |clause| clause.operator == ">=" || clause.operator == "=" }
        .map(&.version)
        .max?
      return nil unless floor
      return nil unless requirement.satisfied_by?(floor)

      floor.to_s
    end

    # Read from doc_versions rather than from doc_build_requests, because this
    # asks whether a reader's cross link would resolve, and that is decided by
    # exactly the column `DependencyIndex` reads. A succeeded request row whose
    # version row was never marked is a version this site will not link to.
    CORE_VERSIONS_SQL = <<-SQL
      SELECT doc_versions.version
      FROM doc_versions
      JOIN docs ON docs.id = doc_versions.doc_id
      WHERE docs.package_name = $1
        AND doc_versions.build_status = 'success'
      SQL

    private def core_already_satisfies?(requirement : Semver::Requirement) : Bool
      AppDatabase.query_all(CORE_VERSIONS_SQL, CORE_PACKAGE, as: String).any? do |raw|
        version = Semver::Version.parse?(raw)
        !version.nil? && requirement.satisfied_by?(version)
      end
    end
  end
end
