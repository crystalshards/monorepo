class Api::Posts::Show < ApiAction
  get "/api/posts/:slug" do
    post = PostQuery.new.slug(slug).first?

    unless post
      return json({error: "Post not found"}, status: 404)
    end

    updated_post = SavePost.update!(post, view_count: post.view_count + 1)

    json({
      id:           updated_post.id,
      title:        updated_post.title,
      slug:         updated_post.slug,
      content:      updated_post.content,
      excerpt:      updated_post.excerpt,
      author_name:  updated_post.author_name,
      author_email: updated_post.author_email,
      tags:         updated_post.tags,
      published_at: updated_post.published_at,
      featured:     updated_post.featured,
      view_count:   updated_post.view_count,
      created_at:   updated_post.created_at,
      updated_at:   updated_post.updated_at,
    })
  end
end
