require "../../../services/shard_manifest"
require "../../../services/shard_index_requests"

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
    # Safe on every view: a shard already indexed, already claimed, or
    # claimed within the retry floor, claims nothing and indexes nothing
    # here. This is the one thing that gives a never-indexed shard a way out
    # of "found but not read yet" other than waiting for IndexSweep to reach
    # it on its own six-hourly schedule. A winning claim indexes inline, so
    # the reassignment below is what makes the rest of this method see the
    # shard it just populated rather than the empty one it was handed.
    shard = ShardIndexRequests.request(shard) || shard

    # Semver, not released_at. Only the version the indexer actually fetched
    # carries a real commit date; every other row falls back to the repository's
    # pushed_at, so a date sort returns them in an order Postgres chose. Measured
    # on kemal: 64 of its 65 rows share one instant and 1.9.0 sorted above
    # 1.11.0, while the shard's own latest_version said 1.12.0.
    versions = VersionOrder.sort_versions(shard.shard_versions)

    selected = if requested = requested_version
                 versions.find { |candidate| candidate.version == requested }
               else
                 # The same rule the indexer used to choose latest_version, so
                 # the selector's default, the card and the API cannot disagree
                 # about which version this shard is on.
                 VersionOrder.latest_version(versions)
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
      manifest: StoredManifest.from(selected),
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
