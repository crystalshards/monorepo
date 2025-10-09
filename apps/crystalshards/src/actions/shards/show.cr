class Shards::Show < BrowserAction
  get "/shards/:shard_name" do
    shard = ShardQuery.new
      .preload_shard_versions
      .name(shard_name)
      .first?

    if shard.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    versions = shard.shard_versions.sort_by(&.released_at).reverse
    latest_version = versions.first?

    dependencies = if latest_version
                     DependencyQuery.new
                       .shard_version_id(latest_version.id.not_nil!)
                       .scope("runtime").to_a
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
