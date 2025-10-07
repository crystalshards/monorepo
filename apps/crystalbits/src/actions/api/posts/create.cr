class Api::Posts::Create < ApiAction
  include Lucky::RateLimit
  rate_limit to: 10, within: 1.hour

  post "/api/posts" do
    SavePost.create(params) do |operation, post|
      if post
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
        }, status: 201)
      else
        json({
          errors: operation.errors.map { |attr, msgs| {attr.to_s => msgs} },
        }, status: 422)
      end
    end
  end
end
