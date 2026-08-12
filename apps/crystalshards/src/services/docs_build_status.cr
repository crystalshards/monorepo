require "../docs_database"

module CrystalShards
  # Reports documentation build progress back to crystaldocs.
  #
  # crystaldocs shows a reader a pending page while a build runs and a failure
  # when one fails, and it refuses to re-queue a version for an hour after a
  # failure. All three depend on this: without a status write, a failed build
  # is indistinguishable from a queued one, the pending page spins forever and
  # the retry floor has no failed_at to measure from.
  #
  # Only the outcome columns are written. crystaldocs owns the request itself.
  class DocsBuildStatus
    # An outcome that could not be written down.
    #
    # This exists so a caller can tell "the build failed" from "the build's
    # result was lost", which are different facts with different repairs. The
    # builder's own rescue path used to be reached by both, and would then
    # record a failure for a build that had in fact succeeded.
    class Unrecorded < Exception
      def initialize(outcome : String, package_name : String, version : String, cause : Exception)
        super(
          "could not record the #{outcome} outcome of #{package_name}@#{version} in the crystaldocs " \
          "database: #{cause.message.presence || cause.class.name}. Neither the build request nor the " \
          "version row was changed, so the documentation site still shows this version exactly as it " \
          "did before the build ran.",
          cause
        )
      end
    end

    # Compiler output from a shard that does not build can run to tens of
    # kilobytes. The page shows this verbatim, and the useful part is at the
    # start, so it is capped rather than stored whole.
    MAX_ERROR_LENGTH = 4000

    BUILDING_SQL = <<-SQL
      UPDATE doc_build_requests
      SET status = 'building',
          started_at = $3,
          finished_at = NULL,
          failed_at = NULL,
          last_error = NULL,
          updated_at = $3
      WHERE package_name = $1 AND version = $2
      SQL

    SUCCEEDED_SQL = <<-SQL
      UPDATE doc_build_requests
      SET status = 'succeeded',
          finished_at = $3,
          failed_at = NULL,
          last_error = NULL,
          updated_at = $3
      WHERE package_name = $1 AND version = $2
      SQL

    # failed_at is the column crystaldocs measures its retry floor from, so it
    # is set on every failure path, including the ones that fail before any
    # cloning happens.
    FAILED_SQL = <<-SQL
      UPDATE doc_build_requests
      SET status = 'failed',
          finished_at = $3,
          failed_at = $3,
          last_error = $4,
          updated_at = $3
      WHERE package_name = $1 AND version = $2
      SQL

    # doc_versions carries its own build_status, and until now nothing on
    # either side of the boundary ever wrote it. package_registration inserts
    # the row with 'pending' and that is where it stayed, for every version of
    # every package, however many builds succeeded.
    #
    # It is not a duplicate of the request row. A build the registry indexer
    # commissioned has no request row at all, because nobody asked for it from
    # a page, so the request table cannot answer "does this version have
    # documentation" for most of the catalogue. doc_versions can: crystaldocs
    # registers one row per published version regardless of who built it.
    #
    # That is why the docs site's cross-package links were silently off
    # everywhere: DependencyIndex asks for versions whose build_status is
    # 'success', and nothing had ever set it.
    #
    # The spelling differs from the request row on purpose, because the column
    # is constrained to pending/building/success/failed and predates this.
    VERSION_BUILDING_SQL = <<-SQL
      UPDATE doc_versions
      SET build_status = 'building', updated_at = $3
      WHERE version = $2
        AND doc_id IN (SELECT id FROM docs WHERE package_name = $1)
      SQL

    VERSION_SUCCEEDED_SQL = <<-SQL
      UPDATE doc_versions
      SET build_status = 'success', updated_at = $3
      WHERE version = $2
        AND doc_id IN (SELECT id FROM docs WHERE package_name = $1)
      SQL

    VERSION_FAILED_SQL = <<-SQL
      UPDATE doc_versions
      SET build_status = 'failed', updated_at = $3
      WHERE version = $2
        AND doc_id IN (SELECT id FROM docs WHERE package_name = $1)
      SQL

    def initialize(@package_name : String, @version : String)
    end

    # The one state that is allowed to go unrecorded.
    #
    # Nothing durable is lost when this write fails. Both columns already read
    # what a reader is already being shown, and whichever outcome follows
    # overwrites them from scratch rather than stepping forward from here, so
    # the only cost is that the pending page says "pending" instead of
    # "building" for the length of one build. Raising would abandon a build
    # that was about to succeed in order to report that it had started.
    #
    # Not silent, though: `record` has already logged the failure at error
    # level against this package and version before raising, so a docs
    # database that has stopped accepting writes is visible from the first
    # build rather than from the first outcome.
    def building : Nil
      record("building", BUILDING_SQL, VERSION_BUILDING_SQL)
    rescue Unrecorded
    end

    def succeeded : Nil
      record("succeeded", SUCCEEDED_SQL, VERSION_SUCCEEDED_SQL)
    end

    def failed(reason : String?) : Nil
      record("failed", FAILED_SQL, VERSION_FAILED_SQL, truncate(reason))
    end

    # One outcome, one transaction, and no swallowing.
    #
    # The two statements describe the same build. Written separately, a failure
    # between them left crystaldocs holding a request row that said 'succeeded'
    # beside a version row that still said 'pending', and nothing anywhere
    # reconciles those afterwards. In one transaction an outcome lands in both
    # tables or in neither, so the pair can be stale but never contradictory.
    #
    # An outcome that cannot be recorded raises, because the outcome of a build
    # is durable state and nothing re-derives it: the artifact is in the bucket
    # and unreferenced, the version reads 'pending' forever, DependencyIndex
    # skips it forever, and the retry floor has no failed_at to measure from.
    # Raising fails the job, which is what puts the request back on the queue
    # to be built and recorded again. Rebuilding a shard is cheap next to a
    # catalogue entry that is permanently wrong.
    #
    # `building` is the one caller that rescues this, for the reason given
    # there.
    private def record(outcome : String, request_sql : String, version_sql : String, error : String? = nil) : Nil
      now = Time.utc
      requests = 0_i64
      versions = 0_i64

      # Scoped to the write alone, so the receipt below cannot be reported as a
      # lost outcome and the message about nothing having changed is always
      # true of what actually happened.
      begin
        DocsDatabase.transaction do
          result =
            if error
              DocsDatabase.exec(request_sql, @package_name, @version, now, error)
            else
              DocsDatabase.exec(request_sql, @package_name, @version, now)
            end

          requests = result.rows_affected
          versions = DocsDatabase.exec(version_sql, @package_name, @version, now).rows_affected
        end
      rescue ex : Exception
        Log.error(exception: ex) do
          "DocsBuildStatus: could not record the #{outcome} outcome of #{@package_name}@#{@version}. " \
          "The transaction was rolled back, so neither doc_build_requests nor doc_versions was changed " \
          "and the documentation site still shows this version as it was before the build."
        end

        raise Unrecorded.new(outcome, @package_name, @version, ex)
      end

      # The receipt. A statement that matched no row succeeds and records
      # nothing, which is a normal outcome for the request table and an
      # entirely different fact from one that landed; the counts are the only
      # thing that can tell those apart once the build is over.
      Log.info do
        "DocsBuildStatus: recorded #{outcome} for #{@package_name}@#{@version} " \
        "(#{requests} request row#{"s" unless requests == 1}, #{versions} version row#{"s" unless versions == 1})"
      end
    end

    private def truncate(reason : String?) : String
      text = reason.presence || "The build failed without reporting a reason."
      return text if text.size <= MAX_ERROR_LENGTH

      "#{text[0, MAX_ERROR_LENGTH]}\n... truncated"
    end
  end
end
