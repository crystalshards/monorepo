class AddProviderFieldsToShards::V00000000000011 < Avram::Migrator::Migration::V1
  def migrate
    alter table_for(Shard) do
      add provider : String, default: "github"
      add repository_type : String, default: "git"
    end
  end

  def rollback
    alter table_for(Shard) do
      remove :provider
      remove :repository_type
    end
  end
end
