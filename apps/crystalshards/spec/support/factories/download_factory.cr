class DownloadFactory < Avram::Factory
  def initialize
    shard_version_id ShardVersionFactory.create.id
    shard_id ShardFactory.create.id
    downloaded_at Time.utc
    ip_address "127.0.0.1"
    user_agent "Test Agent"
  end
end
