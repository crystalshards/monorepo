class Home::Index < BrowserAction
  get "/" do
    # How many shards carry a star count at all, and what those add up to.
    # Both numbers are needed, because they answer different questions: a sum
    # of zero across shards we have measured means nobody has starred them,
    # while a sum of zero across shards we have never fetched means we do not
    # know yet. The homepage has to be able to tell those apart.
    shards_with_stars, total_stars = ShardPopularity.star_totals

    # "Most starred" is only a claim worth making once something has been
    # starred. With no star coverage this would rank six shards by a value none
    # of them have, so the section is not rendered at all rather than
    # presenting crawl order as a popularity ranking.
    #
    # nulls_last matters here and was previously missing: Postgres sorts NULLs
    # FIRST on a DESC order, so a plain `github_stars.desc_order` led the
    # "Most starred" section with the shards that have no star count.
    featured_shards = if shards_with_stars > 0
                        ShardQuery.new
                          .preload_shard_versions
                          .github_stars.desc_order(:nulls_last)
                          .limit(6)
                          .to_a
                      else
                        [] of Shard
                      end

    recent_shards = ShardQuery.new
      .preload_shard_versions
      .updated_at.desc_order
      .limit(6)
      .to_a

    total_shards = ShardQuery.new.select_count
    total_dependency_links = ShardPopularity.dependency_link_total

    # Both card sections counted in a single query. Featured and recent overlap
    # while the registry is small, hence the uniq.
    dependent_counts = ShardPopularity.dependent_counts(
      (featured_shards + recent_shards).map(&.id).uniq
    )

    html Home::IndexPage,
      featured_shards: featured_shards,
      recent_shards: recent_shards,
      dependent_counts: dependent_counts,
      total_shards: total_shards,
      total_dependency_links: total_dependency_links,
      total_stars: total_stars,
      shards_with_stars: shards_with_stars
  end
end
