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
    total_count = filtered.select_count

    # A search this registry could not answer is taken to GitHub, once, and the
    # page is rendered from whatever that found.
    #
    # The sweep has finished: github.com reported completed_exhaustive, so a
    # query returning nothing here is usually a query for something the one
    # enumeration we run could never have seen, rather than one that was too
    # early. The visitor has just said exactly what they were looking for, which
    # is a better query than any partition of file sizes, and it costs one
    # request to ask it.
    #
    # ShardSearchProbe decides whether a probe is worth running at all: it is
    # off without a credential, ignores short terms, ignores searches the
    # registry already answered, and probes any one term at most once a day.
    # Everything here has to know is whether new rows appeared, because the
    # count and the page were both read before they did.
    if registered = ShardSearchProbe.request(query, total_count)
      if registered > 0
        total_count = filtered.select_count
      end
    end

    paginated_shards = filtered
      .sort_by_column(sort)
      .limit(per_page)
      .offset((page - 1) * per_page)
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

  # The search and its filters, without an order or a page.
  #
  # Built on demand rather than once into a local, because a probe that
  # registers rows makes any query built before it stale. Two calls to this are
  # two queries against the same criteria; one query object reused across a
  # write would be the same criteria against a snapshot that has moved.
  private def filtered : ShardQuery
    shards_query = ShardQuery.new.preload_shard_versions

    # Search matches name, description and identity, so two shards sharing a
    # name both appear, each with its own host and its own URL.
    if search_query = query
      shards_query = shards_query.search(search_query)
    end

    if filter_license = license
      shards_query = shards_query.license(filter_license)
    end

    if filter_min_stars = min_stars
      shards_query = shards_query.github_stars.gte(filter_min_stars)
    end

    if filter_has_docs = has_docs
      shards_query = shards_query.documentation_url.is_not_nil if filter_has_docs
    end

    shards_query
  end
end
