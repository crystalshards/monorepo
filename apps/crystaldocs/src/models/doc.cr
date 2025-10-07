class Doc < BaseModel
  table do
    column package_name : String
    column current_version : String?
    column description : String?
    column repository_url : String?
    column total_views : Int64
    column last_updated_at : Time?

    has_many doc_versions : DocVersion
  end
end
