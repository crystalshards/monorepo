class Shard < BaseModel
  table do
    column name : String
    column description : String
    column repository_url : String
    column homepage_url : String
    column documentation_url : String
    column license : String
    column total_downloads : Int64
    column github_stars : Int32
    column github_forks : Int32
    column last_synced_at : Time

    has_many shard_versions : ShardVersion
    has_many dependencies : Dependency
    has_many downloads : Download
  end
end
