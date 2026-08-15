class DocVersion < BaseModel
  table do
    column version : String
    column published_at : Time
    column build_status : String
    column storage_path : String
    column file_count : Int32?
    column total_size : Int64?
    column metadata : JSON::Any?
    # The commit the artifact was actually built from, not the version
    # string: a git tag can be moved after the fact, and only the commit
    # traces an artifact back to the exact source it documents. Nullable
    # because every row that predates this column has no such record, and
    # backfilling one without proof of what was actually built would be a
    # guess wearing the shape of a fact.
    column source_commit_sha : String?

    belongs_to doc : Doc
  end
end
