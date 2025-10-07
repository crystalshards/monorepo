class CreateShardVersions::V00000000000003 < Avram::Migrator::Migration::V1
  def migrate
    enable_extension "btree_gin"

    create table_for(ShardVersion) do
      primary_key id : Int64
      add_timestamps
      add_belongs_to shard : Shard, on_delete: :cascade, index: true
      add version : String
      add yanked : Bool, default: false
      add released_at : Time, index: true
      add commit_sha : String?
      add crystal_version : String?
      add metadata : JSON::Any?
    end

    create_index table_for(ShardVersion), [:shard_id, :version], unique: true
  end

  def rollback
    drop_index table_for(ShardVersion), [:shard_id, :version]
    drop table_for(ShardVersion)
  end
end
