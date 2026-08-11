# Route helpers take a shard's identity, not its name, so specs splat the
# identity of the shard they just created:
#
#   ApiClient.exec(Api::Shards::Show.with(**identity_of(shard)))
#   ApiClient.exec(Api::Shards::Versions::Show.with(**identity_of(shard), version_number: "1.0.0"))
def identity_of(shard : Shard) : NamedTuple(host: String, owner: String, repo: String)
  {
    host:  shard.host.not_nil!,
    owner: shard.owner.not_nil!,
    repo:  shard.repo.not_nil!,
  }
end

# An identity that is deliberately not in the registry, for the 404 paths.
def unregistered_identity : NamedTuple(host: String, owner: String, repo: String)
  {host: "github.com", owner: "nobody", repo: "not-a-real-shard"}
end

# Two shards with one name on two hosts: the case a name-keyed registry could
# not hold. Neither is a duplicate of the other and neither is canonical.
def create_same_name_pair(name : String = "router") : Tuple(Shard, Shard)
  github = ShardFactory.create &.name(name)
    .repository_url("https://github.com/kemalcr/#{name}")
    .description("The GitHub #{name}")
  gitlab = ShardFactory.create &.name(name)
    .repository_url("https://gitlab.com/acme/#{name}")
    .description("The GitLab #{name}")

  {github, gitlab}
end

# The same pair with one published version each, for the paths that need a
# version to act on.
def create_same_name_pair_with_versions(
  name : String = "router",
  version : String = "1.0.0",
) : Tuple(Shard, Shard)
  github, gitlab = create_same_name_pair(name)
  ShardVersionFactory.create &.shard_id(github.id).version(version)
  ShardVersionFactory.create &.shard_id(gitlab.id).version(version)
  {github, gitlab}
end
