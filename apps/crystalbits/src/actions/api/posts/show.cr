class Api::Posts::Show < ApiAction
  get "/api/posts/:slug" do
    post = PostQuery.new.slug(slug).first?

    unless post
      return json({error: "Post not found"}, status: 404)
    end

    post.view_count += 1
    SavePost.update!(post, view_count: post.view_count)

    json({
      id:           post.id,
      title:        post.title,
      slug:         post.slug,
      content:      post.content,
      excerpt:      post.excerpt,
      author_name:  post.author_name,
      author_email: post.author_email,
      tags:         post.tags,
      published_at: post.published_at,
      featured:     post.featured,
      view_count:   post.view_count,
      created_at:   post.created_at,
      updated_at:   post.updated_at,
    })
  end
end
