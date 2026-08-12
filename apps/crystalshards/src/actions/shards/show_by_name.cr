# What /shards/kemal does now that a shard is identified by its repository.
#
# The old URL asked for "the shard called kemal", a question that has one
# answer only while one shard carries that name. So:
#
#   one shard, identified      -> 301 to its canonical URL. Every inbound link
#                                 and bookmark keeps working, and crystaldocs
#                                 links here by name too.
#   one shard, no identity     -> render it. A row the backfill could not parse
#                                 has no canonical URL, and this is the only
#                                 address it has ever had.
#   several shards            -> 302 to search. There is no correct single
#                                 answer, and showing an arbitrary one of two
#                                 repositories is how you install the wrong
#                                 dependency. Search shows both, with their
#                                 hosts, and both link to their own URL.
#   none                      -> 404.
class Shards::ShowByName < BrowserAction
  get "/shards/:shard_name" do
    matches = ShardQuery.new
      .preload_shard_versions
      .name(shard_name)
      .limit(2)
      .to_a

    case matches.size
    when 0
      raise Lucky::RouteNotFoundError.new(context)
    when 1
      redirect_or_render(matches.first)
    else
      redirect to: Shards::Index.with(query: shard_name).path
    end
  end

  private def redirect_or_render(shard : Shard)
    if slug = shard.canonical_slug
      parts = slug.split('/')
      redirect to: Shards::Show.with(
        host: parts[0],
        owner: parts[1],
        repo: parts[2]
      ).path, status: 301
    else
      render_legacy_shard(shard)
    end
  end

  # Mirrors Shards::Show for the one case that cannot be redirected there.
  private def render_legacy_shard(shard : Shard)
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
