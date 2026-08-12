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

    def building : Nil
      write(BUILDING_SQL)
      write(VERSION_BUILDING_SQL)
    end

    def succeeded : Nil
      write(SUCCEEDED_SQL)
      write(VERSION_SUCCEEDED_SQL)
    end

    def failed(reason : String?) : Nil
      write(FAILED_SQL, truncate(reason))
      write(VERSION_FAILED_SQL)
    end

    # A build that cannot be reported is still a build. If the docs database
    # is unreachable the artifact may well have been produced and uploaded, so
    # this never interrupts the job; it logs loudly and lets the build stand.
    #
    # No row is a normal outcome, not an error: a build triggered by the
    # registry indexer rather than by someone opening a docs page has nobody
    # waiting on it and nothing to update.
    private def write(sql : String, error : String? = nil) : Nil
      now = Time.utc

      if error.nil?
        DocsDatabase.exec(sql, @package_name, @version, now)
      else
        DocsDatabase.exec(sql, @package_name, @version, now, error)
      end
    rescue ex : Exception
      Log.error(exception: ex) do
        "DocsBuildStatus: could not record build state for #{@package_name}@#{@version}. The docs site will keep showing this version as still building until it is asked for again."
      end
    end

    private def truncate(reason : String?) : String
      text = reason.presence || "The build failed without reporting a reason."
      return text if text.size <= MAX_ERROR_LENGTH

      "#{text[0, MAX_ERROR_LENGTH]}\n... truncated"
    end
  end
end
