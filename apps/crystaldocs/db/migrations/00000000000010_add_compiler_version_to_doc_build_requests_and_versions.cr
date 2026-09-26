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
  # WHY LEGACY ROWS ARE NOT BACKFILLED HERE.
  #
  # Legacy failed rows are left with compiler_version NULL. The first post-deploy
  # reconcile-docs-status Job adopts any NULL-compiler failures into the toolchain
  # current at deploy time, rather than this migration hardcoding a version string.
  # This avoids asserting an unverified claim about which image historical rows
  # were built under, while ensuring the deploy that ships this retries none of them.
  def migrate
    alter table_for(DocBuildRequest) do
      add compiler_version : String?
    end

    alter table_for(DocVersion) do
      add compiler_version : String?
    end
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
