class Shards::Index < BrowserAction
  # Popularity is the default order, not recency.
  #
  # The crawler walks GitHub's search results bisected on shard.yml byte size
  # ascending, so every row was discovered in roughly one burst and
  # "recently updated" is very nearly crawl order. That surfaces the smallest
  # manifests on the internet first, which is why the front page of this
  # registry currently reads as a pile of abandoned test projects. Ranking by
  # what other shards actually depend on, then by stars, puts the
  # load-bearing packages on the first page instead.
  param page : Int32 = 1
  param per_page : Int32 = 20
  param query : String?
  param sort : String = "popular"
  param license : String?
  param min_stars : Int32?
  param has_docs : Bool?

  get "/shards" do
    shards_query = ShardQuery.new
      .preload_shard_versions

    # Search matches name, description and identity, so two shards sharing a
    # name both appear, each with its own host and its own URL.
    if search_query = query
      shards_query = shards_query.search(search_query)
    end

    # Apply license filter
    if filter_license = license
      shards_query = shards_query.license(filter_license)
    end

    # Apply minimum stars filter
    if filter_min_stars = min_stars
      shards_query = shards_query.github_stars.gte(filter_min_stars)
    end

    # Apply has documentation filter
    if filter_has_docs = has_docs
      shards_query = shards_query.documentation_url.is_not_nil if filter_has_docs
    end

    # One definition of the sorts, on ShardQuery. An unrecognised sort, which
    # now includes the retired "downloads", falls through to popularity rather
    # than erroring: an old bookmark still returns a sensible page.
    shards_query = shards_query.sort_by_column(sort)

    total_count = shards_query.select_count
    offset_value = (page - 1) * per_page

    paginated_shards = shards_query
      .limit(per_page)
      .offset(offset_value)
      .to_a

    # Every card shows a dependent count, so the whole page is counted in one
    # query here. A card resolving its own count would be an N+1 that grows
    # with per_page.
    dependent_counts = ShardPopularity.dependent_counts(paginated_shards.map(&.id))

    html Shards::IndexPage,
      shards: paginated_shards,
      dependent_counts: dependent_counts,
      query: query,
      sort: sort,
      license: license,
      min_stars: min_stars,
      has_docs: has_docs,
      page: page,
      per_page: per_page,
      total_count: total_count
  end
end
