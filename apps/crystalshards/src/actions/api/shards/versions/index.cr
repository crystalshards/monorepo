class Api::Shards::Versions::Index < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/shards/:shard_name/versions" do
    shard = ShardQuery.new
      .preload_shard_versions
      .name(shard_name)
      .first?

    if shard.nil?
      head 404
    else
      json({
        shard_name: shard.name,
        versions:   shard.shard_versions.map do |version|
          {
            version:     version.version,
            released_at: version.released_at,
            yanked:      version.yanked,
            commit_sha:  version.commit_sha,
            downloads:   DownloadQuery.new.shard_version_id(version.id.not_nil!).select_count,
          }
        end,
      })
    end
  end
end
