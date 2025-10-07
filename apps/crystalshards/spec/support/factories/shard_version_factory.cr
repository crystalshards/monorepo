class ShardVersionFactory < Avram::Factory
  def initialize
    shard_id ShardFactory.create.id
    version "1.0.0"
    released_at Time.utc
    yanked false
  end
end
