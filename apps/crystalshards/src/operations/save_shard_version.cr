class SaveShardVersion < ShardVersion::SaveOperation
  permit_columns :version, :yanked, :released_at, :commit_sha,
    :crystal_version, :metadata

  before_save do
    validate_required version, released_at, shard_id
  end
end
