class Api::Shards::Versions::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/shards/:shard_name/:version_number" do
    shard = ShardQuery.new.name(shard_name).first?

    if shard.nil?
      head 404
    else
      version = ShardVersionQuery.new
        .shard_id(shard.id.not_nil!)
        .version(version_number)
        .preload_dependencies
        .preload_downloads
        .first?

      if version.nil?
        head 404
      else
        json({
          shard_name:   shard.name,
          version:      version.version,
          released_at:  version.released_at,
          yanked:       version.yanked,
          commit_sha:   version.commit_sha,
          downloads:    version.downloads.size,
          dependencies: version.dependencies.map do |dep|
            {
              name:                dep.name,
              version_requirement: dep.version_requirement,
              scope:               dep.scope,
            }
          end,
        })
      end
    end
  end
end
