class CreateOwners::V00000000000006 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Owner) do
      primary_key id : Int64
      add_timestamps
      add_belongs_to user : User, on_delete: :cascade, index: true
      add_belongs_to shard : Shard, on_delete: :cascade, index: true
      add role : String, default: "maintainer"

      add_index :user_id, :shard_id, unique: true
    end
  end

  def rollback
    drop table_for(Owner)
  end
end
