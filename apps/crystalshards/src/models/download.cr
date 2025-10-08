class Download < BaseModel
  table do
    column downloaded_at : Time
    column ip_address : String
    column user_agent : String
    column country_code : String

    belongs_to shard : Shard
    belongs_to shard_version : ShardVersion
  end
end
