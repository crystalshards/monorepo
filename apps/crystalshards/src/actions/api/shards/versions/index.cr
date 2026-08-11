class Api::Shards::Versions::Index < ApiAction
  include Api::Auth::SkipRequireAuthToken

  # "versions" is a static segment, so LuckyRouter matches it ahead of the
  # :version_number parameter on Api::Shards::Versions::Show.
  get "/api/shards/:host/:owner/:repo/versions" do
    shard = ShardQuery.new
      .preload_shard_versions
      .canonical_slug("#{host}/#{owner}/#{repo}")
      .first?

    if shard.nil?
      head 404
    else
      json({
        name:           shard.name,
        canonical_slug: shard.canonical_slug,
        versions:       shard.shard_versions.map do |version|
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
