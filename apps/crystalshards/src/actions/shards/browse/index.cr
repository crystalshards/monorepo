class Shards::Browse::Index < BrowserAction
  get "/shards" do
    query = params.get?(:query)
    license = params.get?(:license)
    min_stars = params.get?(:min_stars).try(&.to_i?)
    sort = params.get?(:sort) || "updated"
    direction = params.get?(:direction) || "desc"
    page = params.get?(:page).try(&.to_i) || 1

    shards_query = ShardQuery.new
      .search(query)
      .by_license(license)
      .with_min_stars(min_stars)
      .sort_by_column(sort, direction)
      .preload_shard_versions

    total_count = shards_query.select_count
    shards = shards_query
      .paginate(page: page, per_page: 20)
      .results

    total_pages = (total_count / 20.0).ceil.to_i

    html Shards::Browse::IndexPage,
      shards: shards,
      query: query,
      license: license,
      min_stars: min_stars,
      sort: sort,
      direction: direction,
      page: page,
      total_pages: total_pages,
      total_count: total_count
  end
end
