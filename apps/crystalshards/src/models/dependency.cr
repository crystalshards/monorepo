class Dependency < BaseModel
  table do
    column name : String
    column version_requirement : String
    column scope : String

    belongs_to shard_version : ShardVersion
    # TEMPORARILY COMMENTED OUT due to Avram 1.4.2 bug with nilable foreign keys
    # belongs_to dependent_shard : Shard?
  end
end
