class CreateOwners::V00000000000006 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Owner) do
      primary_key id : Int64
      add_timestamps
      add_belongs_to user : User, on_delete: :cascade
      add_belongs_to shard : Shard, on_delete: :cascade
      add role : String, default: "maintainer"
    end

    create_index table_for(Owner), [:user_id, :shard_id], unique: true
  end

  def rollback
    drop_index table_for(Owner), [:user_id, :shard_id]
    drop table_for(Owner)
  end
end
