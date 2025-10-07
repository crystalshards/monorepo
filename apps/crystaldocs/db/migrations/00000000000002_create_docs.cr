class CreateDocs::V00000000000002 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(Doc) do
      primary_key id : Int64
      add_timestamps
      add package_name : String, unique: true, index: true
      add current_version : String?
      add description : String?
      add repository_url : String?
      add total_views : Int64, default: 0
      add last_updated_at : Time?
    end
  end

  def rollback
    drop table_for(Doc)
  end
end
