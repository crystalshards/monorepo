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
      # Newest first, by the same rule the page and the detail payload use.
      # This endpoint exists to be read top-down, and database order is
      # insertion order: on kemal that put 1.13.0 last, behind 64 tags
      # recorded in one earlier pass.
      json({
        name:           shard.name,
        canonical_slug: shard.canonical_slug,
        versions:       VersionOrder.sort_versions(shard.shard_versions).map do |version|
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
