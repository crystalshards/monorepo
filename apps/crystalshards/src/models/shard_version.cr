class ShardVersion < BaseModel
  table do
    column version : String
    column yanked : Bool
    column released_at : Time
    column commit_sha : String?
    column crystal_version : String?
    column metadata : JSON::Any?

    belongs_to shard : Shard
    has_many dependencies : Dependency
    has_many downloads : Download
  end
end
