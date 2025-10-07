class CreateDocVersions::V00000000000003 < Avram::Migrator::Migration::V1
  def migrate
    create table_for(DocVersion) do
      primary_key id : Int64
      add_timestamps
      add_belongs_to doc : Doc, on_delete: :cascade, index: true
      add version : String, index: true
      add published_at : Time
      add build_status : String, default: "pending"
      add storage_path : String
      add file_count : Int32?
      add total_size : Int64?
      add metadata : JSON::Any?
    end

    create_index table_for(DocVersion), [:doc_id, :version], unique: true
  end

  def rollback
    drop table_for(DocVersion)
  end
end
