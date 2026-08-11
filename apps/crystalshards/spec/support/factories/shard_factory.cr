class ShardFactory < Avram::Factory
  # Avram wires a factory to the GENERATED Shard::SaveOperation, which knows
  # nothing about identity: a factory shard would be created with no host, no
  # owner, no repo and no canonical_slug, and specs would be exercising a row
  # shape production can never produce. Point it at SaveShard instead, so
  # factories derive identity exactly the way every real write does.
  def initialize
    @operation = SaveShard.new

    slug = UUID.random.to_s[0..7]

    name "sample-shard-#{slug}"
    repository_url "https://github.com/crystal-lang/sample-shard-#{slug}"
    description "A sample Crystal shard"
    total_downloads 0
    provider "github"
    repository_type "git"
  end

  # Places the shard at a specific repository, which is what makes two shards
  # able to share a name.
  def at(host : String, owner : String, repo : String)
    repository_url "https://#{host}/#{owner}/#{repo}"
    self
  end
end
