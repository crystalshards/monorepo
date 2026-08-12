class ShardVersionFactory < Avram::Factory
  def initialize
    shard_id ShardFactory.create.id
    version "1.0.0"
    released_at Time.utc
    yanked false

    # A factory writes through Avram's own operation, not SaveShardVersion, so
    # the default that operation applies does not reach here. Every version a
    # spec creates without saying otherwise is a tagged release, which is what
    # every one of them meant before the column existed.
    source ShardVersion::Source::TAG
  end
end
