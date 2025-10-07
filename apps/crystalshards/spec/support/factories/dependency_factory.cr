class DependencyFactory < Avram::Factory
  def initialize
    shard_version_id ShardVersionFactory.create.id
    name "example_dependency"
    version_requirement "~> 1.0"
    scope "runtime"
  end
end
