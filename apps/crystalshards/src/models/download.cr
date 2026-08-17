# A download is a count against a version. It carries no address: the
# identifying half of a download record buys nothing the count needs, and
# the page view collector holds the rest of the site to the same rule.
class Download < BaseModel
  table do
    column downloaded_at : Time
    column user_agent : String?
    column country_code : String?

    belongs_to shard : Shard
    belongs_to shard_version : ShardVersion
  end
end
