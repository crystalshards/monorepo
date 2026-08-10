class AddReadmeToShards::V00000000000012 < Avram::Migrator::Migration::V1
  def migrate
    alter table_for(Shard) do
      add readme_content : String?
    end
  end

  def rollback
    alter table_for(Shard) do
      remove :readme_content
    end
  end
end
