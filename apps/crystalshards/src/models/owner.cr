class Owner < BaseModel
  table do
    column role : String, default: "maintainer"

    belongs_to user : User
    belongs_to shard : Shard
  end
end
