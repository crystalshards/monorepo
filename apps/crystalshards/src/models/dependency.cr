class Dependency < BaseModel
  table do
    column name : String
    column version_requirement : String
    column scope : String

    belongs_to shard_version : ShardVersion
    belongs_to dependent_shard : Shard?
  end
end
