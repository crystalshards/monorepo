class CreateShards::V00000000000002 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Shard) do
      primary_key id : Int64
      add_timestamps
      add name : String, unique: true, index: true
      add description : String?
      add repository_url : String
      add homepage_url : String?
      add documentation_url : String?
      add license : String?
      add total_downloads : Int64, default: 0
      add github_stars : Int32?
      add github_forks : Int32?
      add last_synced_at : Time?
    end
  end

  def rollback
    drop table_for(Shard)
  end
end
