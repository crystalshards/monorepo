class Api::Shards::Index < ApiAction
  include Api::Auth::SkipRequireAuthToken

  param page : Int32 = 1
  param per_page : Int32 = 20
  param query : String?

  get "/api/shards" do
    shards_query = ShardQuery.new
      .preload_shard_versions
      .created_at.desc_order

    if search_query = query
      shards_query = shards_query.search(search_query)
    end

    total_count = shards_query.select_count
    offset_value = (page - 1) * per_page

    paginated_shards = shards_query
      .limit(per_page)
      .offset(offset_value)

    json({
      shards: paginated_shards.map { |shard| ShardPayload.summary(shard) },
      meta:   {
        page:     page,
        per_page: per_page,
        total:    total_count,
      },
    })
  end
end
