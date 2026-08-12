require "../../../services/shard_manifest"

# Everything three routes need in order to render one shard page.
#
# /shards/:host/:owner/:repo               the latest release
# /shards/:host/:owner/:repo/versions/:v   one named release
# /shards/:shard_name                      a legacy row with no identity
#
# All three show the same page, and the only thing that differs is which
# version was asked for, so the assembly lives here instead of being copied
# into each action and drifting.
module Shards::RendersShowPage
  # How many dependents the sidebar names before it stops naming them.
  DEPENDENTS_SHOWN = 12

  private def render_show_page(shard : Shard, requested_version : String? = nil)
    versions = shard.shard_versions.sort_by(&.released_at).reverse

    selected = if requested = requested_version
                 versions.find { |candidate| candidate.version == requested }
               else
                 versions.first?
               end

    # A URL naming a release this shard never published is not a sparse page,
    # it is the wrong page, and saying so is the only honest answer.
    if requested_version && selected.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    shard_id = shard.id.not_nil!

    html Shards::ShowPage,
      shard: shard,
      versions: versions,
      selected_version: selected,
      dependencies: dependencies_for(selected),
      manifest: ShardManifest.from(selected),
      dependent_count: ShardPopularity.dependent_count(shard_id),
      dependents: dependents_for(shard_id)
  end

  private def dependencies_for(version : ShardVersion?) : Array(Dependency)
    return [] of Dependency unless version

    DependencyQuery.new
      .shard_version_id(version.id.not_nil!)
      .preload_dependent_shard
      .to_a
  end

  # Two queries, never one per dependent: ids in release order, then one load.
  # An IN query does not preserve the order the ids arrived in, so it is
  # restored here rather than left to the database to decide.
  private def dependents_for(shard_id : Int64) : Array(Shard)
    ids = ShardPopularity.dependent_ids(shard_id, DEPENDENTS_SHOWN)
    return [] of Shard if ids.empty?

    by_id = {} of Int64 => Shard
    ShardQuery.new.id.in(ids).each { |dependent| by_id[dependent.id.not_nil!] = dependent }

    ids.compact_map { |id| by_id[id]? }
  end
end
