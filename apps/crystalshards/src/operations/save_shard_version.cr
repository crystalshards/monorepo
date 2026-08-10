class SaveShardVersion < ShardVersion::SaveOperation
  permit_columns :version, :yanked, :released_at, :commit_sha,
    :crystal_version, :metadata, :checksum

  before_save do
    validate_required version, released_at, shard_id

    # The (shard_id, version) unique index would otherwise surface a raw
    # Postgres error, so catch the collision as a validation error instead.
    if shard = shard_id.value
      validate_uniqueness_of version, query: ShardVersionQuery.new.shard_id(shard)
    end
  end
end
