class DependencyFactory < Avram::Factory
  def initialize
    shard_version_id ShardVersionFactory.create.id

    # Unique by default, the same way ShardFactory makes a name unique, and for
    # a load-bearing reason rather than tidiness. A version's edges are unique
    # on (shard_version_id, name, scope), because a manifest is a mapping and
    # cannot declare the same dependency twice in one scope. A constant default
    # meant two DependencyFactory.create calls against one version collided on
    # that key, so a spec that only wanted two edges had to know about the
    # constraint to avoid tripping it.
    name "dependency-#{UUID.random.to_s[0..7]}"
    version_requirement "~> 1.0"
    scope "runtime"
  end
end
