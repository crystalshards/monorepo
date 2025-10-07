class ShardVersionBox < Avram::Box
  def initialize
    shard_id ShardBox.create.id
    version "1.0.0"
    released_at Time.utc
    yanked false
  end
end
