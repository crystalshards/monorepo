class CreateDependencies::V00000000000004 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Dependency) do
      primary_key id : Int64
      add_timestamps
      add_belongs_to shard_version : ShardVersion, on_delete: :cascade, index: true
      add_belongs_to dependent_shard : Shard, on_delete: :set_null, optional: true, index: true
      add name : String
      add version_requirement : String
      add scope : String, default: "runtime"

      add_index [:shard_version_id, :name]
    end
  end

  def rollback
    drop table_for(Dependency)
  end
end
