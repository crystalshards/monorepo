class Posts::Index < BrowserAction
  param page : Int32 = 1
  param per_page : Int32 = 20
  param tag : String?
  param search : String?

  get "/posts" do
    query = PostQuery.new.published.recent

    if tag_value = tag
      query = query.by_tag(tag_value)
    end

    if search_value = search
      query = query.search(search_value)
    end

    total_count = query.select_count
    offset_value = (page - 1) * per_page

    posts = query
      .limit(per_page)
      .offset(offset_value)
      .to_a

    html Posts::IndexPage,
      posts: posts,
      current_page: page,
      per_page: per_page,
      total_count: total_count,
      tag: tag,
      search: search
  end
end
