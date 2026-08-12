class SaveShardVersion < ShardVersion::SaveOperation
  permit_columns :version, :yanked, :released_at, :commit_sha,
    :crystal_version, :metadata, :checksum,
    :ref, :source, :spec_yaml, :spec_error, :targets, :executables, :indexed_at

  before_save do
    set_default_values
    validate_required version, released_at, shard_id
    validate_inclusion_of source, in: [ShardVersion::Source::TAG, ShardVersion::Source::BRANCH],
      message: %(must be "#{ShardVersion::Source::TAG}" or "#{ShardVersion::Source::BRANCH}")

    # The (shard_id, version) unique index would otherwise surface a raw
    # Postgres error, so catch the collision as a validation error instead.
    if shard = shard_id.value
      validate_uniqueness_of version, query: ShardVersionQuery.new.shard_id(shard)
    end
  end

  # Rows written before refs were recorded, and callers that only know a
  # version string, both mean a tag. A branch row is always created explicitly.
  private def set_default_values
    source.value ||= ShardVersion::Source::TAG
  end
end
