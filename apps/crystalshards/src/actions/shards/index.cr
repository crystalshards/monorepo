class Shards::Index < BrowserAction
  param page : Int32 = 1
  param per_page : Int32 = 20
  param query : String?

  get "/shards" do
    shards_query = ShardQuery.new
      .preload_shard_versions
      .updated_at.desc_order

    if search_query = query
      shards_query = shards_query.name.ilike("%#{search_query}%")
        .or(&.description.ilike("%#{search_query}%"))
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
      page: page,
      per_page: per_page,
      total_count: total_count
  end
end
