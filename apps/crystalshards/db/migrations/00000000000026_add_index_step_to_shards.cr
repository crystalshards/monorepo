class AddIndexStepToShards::V00000000000026 < Avram::Migrator::Migration::V1
  # Where a running index pass has got to.
  #
  # Indexing a shard reads the repository's refs and metadata, then its
  # shard.yml and README at the newest tag, then writes the versions, then
  # resolves the dependency graph. A visitor who lands on an unindexed shard
  # commissions that pass and was shown one sentence for the whole of it,
  # which is the same complaint the documentation build had.
  #
  # Nullable, and cleared when the pass finishes either way. It is a progress
  # hint rather than a record: nothing reads it afterwards, no retry resumes
  # from it, and a pass whose step writes were all lost still records its
  # outcome correctly in indexed_at and index_error.
  def migrate
    alter table_for(Shard) do
      add index_step : String?
    end
  end

  def rollback
    alter table_for(Shard) do
      remove :index_step
    end
  end
end
