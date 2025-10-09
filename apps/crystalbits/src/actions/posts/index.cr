class Posts::Index < BrowserAction
  param page : Int32 = 1
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

    posts = query.paginate(page: page, per_page: 20)

    html Posts::IndexPage,
      posts: posts,
      current_page: page,
      tag: tag,
      search: search
  end
end
