class DocVersion < BaseModel
  table do
    column version : String
    column published_at : Time
    column build_status : String
    column storage_path : String
    column file_count : Int32?
    column total_size : Int64?
    column metadata : JSON::Any?

    belongs_to doc : Doc
  end
end
