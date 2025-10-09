class Home::Index < BrowserAction
  get "/" do
    featured_post = PostQuery.new.published.featured_only.first?
    recent_posts = PostQuery.new.published.recent.limit(10)

    html Home::IndexPage, featured_post: featured_post, recent_posts: recent_posts
  end
end
