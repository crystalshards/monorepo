class AddChecksumToShardVersions::V00000000000010 < Avram::Migrator::Migration::V1
  def migrate
    alter table_for(ShardVersion) do
      add checksum : String?
    end
  end

  def rollback
    alter table_for(ShardVersion) do
      remove :checksum
    end
  end
end
