class AddSourceCommitShaToDocVersions::V00000000000005 < Avram::Migrator::Migration::V1
  def migrate
    alter table_for(DocVersion) do
      add source_commit_sha : String?
    end
  end

  def rollback
    alter table_for(DocVersion) do
      remove :source_commit_sha
    end
  end
end
