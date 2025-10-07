class DownloadFactory < Avram::Factory
  def initialize
    version = ShardVersionFactory.create
    shard_version_id version.id
    shard_id version.shard_id
    downloaded_at Time.utc
    ip_address "127.0.0.1"
    user_agent "Test Agent"
  end
end
