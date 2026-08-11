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

    versions = shard.shard_versions.sort_by(&.released_at).reverse
    latest_version = versions.first?

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
