# The shape of a shard in the API.
#
# Every payload carries the identity (host, owner, repo, canonical_slug) and
# the registry URL alongside the display name, because a name alone no longer
# tells a client which repository it is looking at. `repository_url` is
# unchanged: it is still the link to the real repository on its host.
module ShardPayload
  def self.summary(shard : Shard)
    {
      name:              shard.name,
      host:              shard.host,
      owner:             shard.owner,
      repo:              shard.repo,
      canonical_slug:    shard.canonical_slug,
      url:               shard.url_path,
      description:       shard.description,
      repository_url:    shard.repository_url,
      homepage_url:      shard.homepage_url,
      documentation_url: shard.documentation_url,
      license:           shard.license,
      total_downloads:   shard.total_downloads,
      github_stars:      shard.github_stars,
      github_forks:      shard.github_forks,
      unavailable_at:    shard.unavailable_at,
      latest_version:    shard.shard_versions.max_by?(&.released_at).try(&.version),
      created_at:        shard.created_at,
      updated_at:        shard.updated_at,
    }
  end

  def self.detail(shard : Shard)
    {
      name:              shard.name,
      host:              shard.host,
      owner:             shard.owner,
      repo:              shard.repo,
      canonical_slug:    shard.canonical_slug,
      url:               shard.url_path,
      description:       shard.description,
      repository_url:    shard.repository_url,
      homepage_url:      shard.homepage_url,
      documentation_url: shard.documentation_url,
      license:           shard.license,
      total_downloads:   shard.total_downloads,
      github_stars:      shard.github_stars,
      github_forks:      shard.github_forks,
      unavailable_at:    shard.unavailable_at,
      created_at:        shard.created_at,
      updated_at:        shard.updated_at,
      versions:          shard.shard_versions.map do |version|
        {
          version:      version.version,
          released_at:  version.released_at,
          yanked:       version.yanked,
          commit_sha:   version.commit_sha,
          downloads:    DownloadQuery.new.shard_version_id(version.id.not_nil!).select_count,
          dependencies: DependencyQuery.new.shard_version_id(version.id.not_nil!).map do |dep|
            {
              name:                dep.name,
              version_requirement: dep.version_requirement,
              scope:               dep.scope,
            }
          end,
        }
      end,
    }
  end
end
