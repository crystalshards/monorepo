require "../docs_database"

module CrystalShards
  # Marks documentation that exists as documentation that exists.
  #
  # WHY THIS IS NEEDED.
  #
  # doc_versions.build_status was written 'pending' when a version was
  # registered and then never written again by anything, on either side of the
  # boundary, until the builder was taught to write it. So every version built
  # before that says 'pending' however many times its documentation was built
  # and published, and nothing else will ever correct them: the builder only
  # writes the outcome of a build it is running now, and no build is going to
  # be run again for a version that already has its artifact.
  #
  # That is not cosmetic. DependencyIndex selects the versions whose
  # build_status is 'success' to decide which dependencies named in a
  # documentation page can link to another package's documentation, so across
  # the whole existing catalogue that set is empty and no cross-package link
  # works.
  #
  # WHAT IT ACCEPTS AS EVIDENCE.
  #
  # An object. A version is marked 'success' when the one artifact a
  # documentation page reads is in the docs bucket, and it is left alone
  # otherwise. Nothing is inferred from the request table, from a timestamp,
  # from whether the shard looks like it ought to have built, or from the row's
  # own storage_path, which records where the artifact WOULD go and is written
  # at registration whether or not anything was ever put there.
  #
  # Absence is not failure. A version nobody has built yet is exactly what
  # 'pending' means, so an absent artifact leaves the row untouched rather than
  # rewriting it to 'failed', which would put a build failure notice on a
  # package whose build has never been asked for.
  #
  # Only 'pending' rows are candidates. 'building', 'success' and 'failed' are
  # all states something wrote deliberately, and the only writer of them is the
  # builder, running now, which will finish what it started.
  #
  # It does not touch doc_build_requests. Most of the catalogue has no request
  # row at all, because one exists only where a reader asked for a build from a
  # page, and an artifact in a bucket says nothing about a request nobody made.
  #
  # Safe to run repeatedly. Every write moves one row from 'pending' to
  # 'success' and is predicated on it still being 'pending', so a second run
  # over the same catalogue finds nothing left to do.
  module DocsStatusReconciliation
    # The one artifact per version. Every documentation page reads this key and
    # no other, and no generated HTML is ever stored, so its presence is the
    # whole question. Named here rather than matched loosely because a bucket
    # also holds build scratch, and scratch under a package prefix must not be
    # read as published documentation.
    ARTIFACT = "docs.json"

    record Candidate, package_name : String, version : String do
      def to_s(io : IO) : Nil
        io << package_name << '@' << version
      end
    end

    # package_name comes from docs rather than from the version row, because the
    # object key is built from the package's canonical name and doc_versions
    # does not carry it.
    PENDING_SQL = <<-SQL
      SELECT d.package_name, v.version
      FROM doc_versions v
      JOIN docs d ON d.id = v.doc_id
      WHERE v.build_status = 'pending'
      ORDER BY d.package_name, v.version
      SQL

    # Predicated on the row still being 'pending', so a build that finishes
    # while this runs keeps its own outcome instead of having this one land on
    # top of it. The argument order matches DocsBuildStatus deliberately: both
    # write this column and a reader comparing them should not have to check
    # which is which.
    MARK_SUCCEEDED_SQL = <<-SQL
      UPDATE doc_versions
      SET build_status = 'success', updated_at = $3
      WHERE version = $2
        AND doc_id IN (SELECT id FROM docs WHERE package_name = $1)
        AND build_status = 'pending'
      SQL

    # What one run did, in the terms an operator needs before and after running
    # it against production.
    class Report
      getter artifacts : Int32
      getter marked = [] of Candidate
      getter unbuilt = 0
      getter overtaken = 0

      def initialize(@artifacts : Int32)
      end

      def mark(candidate : Candidate) : Nil
        @marked << candidate
      end

      def skip_unbuilt : Nil
        @unbuilt += 1
      end

      # The row left 'pending' between the listing and the update, which only a
      # real build does. Counted rather than retried: whatever moved it knows
      # more about that version than this does.
      def skip_overtaken : Nil
        @overtaken += 1
      end

      def examined : Int32
        marked.size + unbuilt + overtaken
      end

      def to_s(io : IO) : Nil
        io << "marked " << marked.size << " of " << examined << " pending version"
        io << "s" unless examined == 1
        io << " as built"
        io << ", " << unbuilt << " with no artifact" if unbuilt > 0
        io << ", " << overtaken << " already moved by a build" if overtaken > 0
      end
    end

    def self.run(store : CrystalStorage::ObjectStore = CrystalStorage.docs) : Report
      # Listed before anything is read out of the database and before anything
      # is written, so an unreachable store is a run that changed nothing rather
      # than a run that marked part of the catalogue and gave up.
      published = published_artifacts(store)
      report = Report.new(published.size)
      now = Time.utc

      Log.info { "Reconciling documentation status against #{published.size} published artifacts in #{store.bucket}" }

      pending.each do |candidate|
        unless published.includes?(CrystalStorage::Keys.docs_json(candidate.package_name, candidate.version))
          report.skip_unbuilt
          next
        end

        rows = DocsDatabase.exec(
          MARK_SUCCEEDED_SQL,
          candidate.package_name,
          candidate.version,
          now
        ).rows_affected

        if rows.zero?
          report.skip_overtaken
        else
          report.mark(candidate)
          Log.info { "#{candidate}: artifact present, marked success" }
        end
      end

      report
    end

    def self.pending : Array(Candidate)
      DocsDatabase.query_all(PENDING_SQL, as: {String, String}).map do |(package_name, version)|
        Candidate.new(package_name: package_name, version: version)
      end
    end

    # One listing of the bucket rather than one existence check per row.
    #
    # The answer for every version is in the same object listing, so a HEAD per
    # row would spend a round trip per version of every package in the
    # catalogue to learn what a few paginated pages already say. It also makes
    # every decision in a run read from one snapshot instead of thousands taken
    # minutes apart.
    #
    # Raises `CrystalStorage::Unavailable` when the store could not answer,
    # which is the point: "the bucket is empty" and "we never saw the bucket"
    # would otherwise both arrive as no rows marked, and the second one must
    # not look like a clean run.
    def self.published_artifacts(store : CrystalStorage::ObjectStore) : Set(String)
      suffix = "/#{ARTIFACT}"
      keys = Set(String).new

      store.list("").each do |key|
        keys << key if key.ends_with?(suffix)
      end

      keys
    end

    def self.render(report : Report, io : IO = STDOUT) : Nil
      io.puts "Documentation status reconciliation"
      io.puts "  Evidence: #{report.artifacts} published #{ARTIFACT} artifacts in the docs bucket."
      io.puts "  Candidates: doc_versions rows whose build_status is still 'pending'."
      io.puts

      if report.examined.zero?
        io.puts "  Nothing was pending. Every registered version already carries the outcome of its build."
      else
        io.puts "  #{report}"
      end

      unless report.marked.empty?
        io.puts
        io.puts "Marked as built:"
        # Capped, because a first run over the whole catalogue marks thousands
        # and a summary nobody can read is not a summary. The count above is
        # complete either way.
        report.marked.first(50).each { |candidate| io.puts "  #{candidate}" }
        remaining = report.marked.size - 50
        io.puts "  ... and #{remaining} more" if remaining > 0
      end

      if report.unbuilt > 0
        io.puts
        io.puts "#{report.unbuilt} version#{"s" unless report.unbuilt == 1} left pending: nothing is in the bucket"
        io.puts "for #{report.unbuilt == 1 ? "it" : "them"}, which is what pending means. Each is built when a reader asks for it."
      end
    end
  end
end
