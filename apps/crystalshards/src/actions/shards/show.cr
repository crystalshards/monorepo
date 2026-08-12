class Shards::Show < BrowserAction
  # The registry addresses a shard by the repository it is, not by its name:
  # /shards/github.com/kemalcr/kemal.
  #
  # Three explicit segments rather than a glob. LuckyRouter registers a glob's
  # base path as well as the glob itself, so /shards/:host/*:rest would also
  # claim /shards/:host and collide with the legacy name route, which crashes
  # the app at boot with DuplicateRouteError. Explicit segments also keep
  # Shards::Show.with(...) working, which a glob route cannot generate.
  get "/shards/:host/:owner/:repo" do
    shard = ShardQuery.new
      .preload_shard_versions
      .canonical_slug("#{host}/#{owner}/#{repo}")
      .first?

    if shard.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    # Semver, not released_at. Only the indexed version carries a real commit
    # date; the rest fall back to the repository's pushed_at, so a date sort
    # ranks 1.9.0 above 1.11.0 and picks a "latest" that contradicts the
    # latest_version stored on the shard itself.
    versions = VersionOrder.sort_versions(shard.shard_versions)
    latest_version = VersionOrder.latest_version(shard.shard_versions)

    dependencies = if latest_version
                     DependencyQuery.new
                       .shard_version_id(latest_version.id.not_nil!)
                       .preload_dependent_shard
                       .to_a
                   else
                     [] of Dependency
                   end

    html Shards::ShowPage,
      shard: shard,
      versions: versions,
      dependencies: dependencies,
      latest_version: latest_version
  end
end
