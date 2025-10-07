class Api::Posts::Index < ApiAction
  get "/api/posts" do
    page = params.get?(:page).try(&.to_i) || 1
    per_page = params.get?(:per_page).try(&.to_i) || 20
    per_page = [per_page, 100].min

    query = PostQuery.new.published.recent

    if tag = params.get?(:tag)
      query = query.by_tag(tag)
    end

    if search_query = params.get?(:q)
      query = query.search(search_query)
    end

    if params.get?(:featured) == "true"
      query = query.featured
    end

    if params.get?(:popular) == "true"
      query = query.popular
    end

    paginated_posts = query.paginate(page: page, per_page: per_page)
    total_count = query.select_count

    json({
      posts:    paginated_posts.map { |post| serialize_post(post) },
      page:     page,
      per_page: per_page,
      total:    total_count,
    })
  end

  private def serialize_post(post : Post)
    {
      id:           post.id,
      title:        post.title,
      slug:         post.slug,
      excerpt:      post.excerpt,
      author_name:  post.author_name,
      tags:         post.tags,
      published_at: post.published_at,
      featured:     post.featured,
      view_count:   post.view_count,
      created_at:   post.created_at,
      updated_at:   post.updated_at,
    }
  end
end
