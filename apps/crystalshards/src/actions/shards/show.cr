class Shards::Show < BrowserAction
  get "/shards/:shard_name" do
    shard = ShardQuery.new
      .preload_shard_versions(ShardVersionQuery.new.preload_downloads)
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

    dependents = find_dependents(shard.name)

    html Shards::ShowPage,
      shard: shard,
      versions: versions,
      dependencies: dependencies,
      latest_version: latest_version,
      dependents: dependents
  end

  private def find_dependents(shard_name : String) : Array(Shard)
    dependencies = DependencyQuery.new
      .name(shard_name)
      .preload_shard_version
      .to_a

    shard_ids = dependencies.map(&.shard_version.shard_id).uniq

    ShardQuery.new
      .id.in(shard_ids)
      .to_a
  end
end
