class Owner < BaseModel
  table do
    column role : String

    belongs_to user : User
    belongs_to shard : Shard
  end
end
