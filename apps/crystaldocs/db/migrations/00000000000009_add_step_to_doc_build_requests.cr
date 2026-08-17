class AddStepToDocBuildRequests::V00000000000009 < Avram::Migrator::Migration::V1
  # Where a running build has got to.
  #
  # A documentation build clones a repository, checks out a version, installs
  # dependencies and runs the compiler, and on a large shard that is minutes.
  # The reader watching it had one undifferentiated "being built" for the whole
  # of it, which is indistinguishable from a stuck queue.
  #
  # Nullable, and cleared by whichever outcome follows. It is a progress hint,
  # not a record: nothing reads it after the build ends, no retry resumes from
  # it, and a build whose step writes were all lost still records its result
  # correctly. The writer is crystalshards, through `DocsBuildStatus`.
  def migrate
    alter table_for(DocBuildRequest) do
      add step : String?
    end
  end

  def rollback
    alter table_for(DocBuildRequest) do
      remove :step
    end
  end
end
