class Shards::Index < BrowserAction
  param page : Int32 = 1
  param per_page : Int32 = 20
  param query : String?
  param sort : String = "updated"
  param license : String?
  param min_stars : Int32?
  param has_docs : Bool?

  get "/shards" do
    shards_query = ShardQuery.new
      .preload_shard_versions

    # Apply search filter
    if search_query = query
      shards_query = shards_query.name.ilike("%#{search_query}%")
        .or(&.description.ilike("%#{search_query}%"))
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

    # Apply sorting
    shards_query = case sort
                   when "popular"
                     shards_query.github_stars.desc_order(:nulls_last)
                   when "name"
                     shards_query.name.asc_order
                   when "downloads"
                     shards_query.total_downloads.desc_order
                   else # "updated"
                     shards_query.updated_at.desc_order
                   end

    total_count = shards_query.select_count
    offset_value = (page - 1) * per_page

    paginated_shards = shards_query
      .limit(per_page)
      .offset(offset_value)
      .to_a

    html Shards::IndexPage,
      shards: paginated_shards,
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
