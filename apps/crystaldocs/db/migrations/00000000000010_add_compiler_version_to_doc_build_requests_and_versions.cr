class AddCompilerVersionToDocBuildRequestsAndVersions::V00000000000010 < Avram::Migrator::Migration::V1
  # Records the Crystal compiler version under which a build failed.
  #
  # WHY THIS COLUMN EXISTS.
  #
  # A deterministic failure (syntax error, deprecated API, macro incompatibility)
  # is terminal for the compiler that compiled it, but not for all future compilers.
  # When the platform toolchain updates, previously failed builds become eligible
  # for retry under the new compiler.
  #
  # WHY THE BACKFILL VALUE WAS CHOSEN.
  #
  # Existing failed rows in production were all produced under the 1.21.0
  # toolchain (the active DocsSandbox image is crystallang/crystal:1.21.0-alpine).
  # If legacy rows were left NULL, the post-deploy reconcile-docs-status Job would
  # treat them as recorded under an unknown toolchain and immediately clear them,
  # re-triggering thousands of doomed builds and defeating the cost reduction.
  #
  # Backfilling existing failed rows with '1.21.0' ensures the upcoming deploy is
  # a no-op for these rows. They will become eligible for retry only when the
  # toolchain advances beyond 1.21.0.
  def migrate
    alter table_for(DocBuildRequest) do
      add compiler_version : String?
    end

    alter table_for(DocVersion) do
      add compiler_version : String?
    end

    # Backfill legacy failed rows to 1.21.0 so the next deploy does not retry them.
    execute <<-SQL
      UPDATE doc_build_requests
      SET compiler_version = '1.21.0'
      WHERE status = 'failed' AND compiler_version IS NULL;
    SQL

    execute <<-SQL
      UPDATE doc_versions
      SET compiler_version = '1.21.0'
      WHERE build_status = 'failed' AND compiler_version IS NULL;
    SQL
  end

  def rollback
    alter table_for(DocBuildRequest) do
      remove :compiler_version
    end

    alter table_for(DocVersion) do
      remove :compiler_version
    end
  end
end
