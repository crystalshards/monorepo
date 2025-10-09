class Posts::Show < BrowserAction
  get "/posts/:slug" do
    post = PostQuery.new.published.slug(slug).first

    increment_view_count(post)

    html Posts::ShowPage, post: post
  end

  private def increment_view_count(post : Post)
    Post::SaveOperation.update!(post, view_count: post.view_count + 1)
  end
end
