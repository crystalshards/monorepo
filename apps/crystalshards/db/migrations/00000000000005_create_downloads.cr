class CreateDownloads::V00000000000005 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Download) do
      primary_key id : Int64
      add_timestamps
      add_belongs_to shard : Shard, on_delete: :cascade, index: true
      add_belongs_to shard_version : ShardVersion, on_delete: :cascade, index: true
      add downloaded_at : Time, index: true
      add ip_address : String?
      add user_agent : String?
      add country_code : String?
    end

    create_index table_for(Download), [:shard_id, :downloaded_at]
    create_index table_for(Download), [:shard_version_id, :downloaded_at]
  end

  def rollback
    drop_index table_for(Download), [:shard_id, :downloaded_at]
    drop_index table_for(Download), [:shard_version_id, :downloaded_at]
    drop table_for(Download)
  end
end
