class Api::Shards::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/shards/:shard_name" do
    shard = ShardQuery.new
      .preload_shard_versions
      .name(shard_name)
      .first?

    if shard.nil?
      head 404
    else
      json({
        name:              shard.name,
        description:       shard.description,
        repository_url:    shard.repository_url,
        homepage_url:      shard.homepage_url,
        documentation_url: shard.documentation_url,
        license:           shard.license,
        total_downloads:   shard.total_downloads,
        github_stars:      shard.github_stars,
        github_forks:      shard.github_forks,
        created_at:        shard.created_at,
        updated_at:        shard.updated_at,
        versions:          shard.shard_versions.map do |version|
          {
            version:      version.version,
            released_at:  version.released_at,
            yanked:       version.yanked,
            commit_sha:   version.commit_sha,
            downloads:    DownloadQuery.new.shard_version_id(version.id).select_count,
            dependencies: DependencyQuery.new.shard_version_id(version.id).map do |dep|
              {
                name:                dep.name,
                version_requirement: dep.version_requirement,
                scope:               dep.scope,
              }
            end,
          }
        end,
      })
    end
  end
end
