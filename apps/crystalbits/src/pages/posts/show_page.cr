class Posts::ShowPage < MainLayout
  needs post : Post

  def page_title
    @post.title
  end

  def content
    article class: "post-content" do
      render_header
      render_body
      render_tags
      render_newsletter_cta
    end
  end

  private def render_header
    header class: "post-header" do
      h1 class: "post-title" do
        text @post.title
      end

      div class: "post-meta" do
        span class: "post-author" do
          text "By #{@post.author_name}"
        end
        span class: "post-separator", "aria-hidden": "true" do
          text "•"
        end
        span class: "post-date" do
          text format_date(@post.published_at)
        end
        span class: "post-separator", "aria-hidden": "true" do
          text "•"
        end
        span class: "post-views" do
          text "#{@post.view_count} views"
        end
      end
    end
  end

  private def render_body
    div class: "post-body" do
      # Post bodies come from the same untrusted places as everything else, so
      # they go through the same door. BitsHtml is the only path to `raw` in
      # this app: Markd in safe mode, then the allowlist sanitiser. The
      # previous `Markd.to_html` here passed raw HTML from a post body
      # straight into the page.
      raw BitsHtml.markdown(@post.content)
    end
  end

  private def render_tags
    return if @post.tags.empty?

    div class: "post-tags-section" do
      # Directly under the article's h1, so this is an h2: heading order must
      # not skip a level.
      h2 "Tags"
      div class: "post-tags" do
        @post.tags.each do |tag|
          a href: "/posts?tag=#{tag}", class: "tag" do
            text tag
          end
        end
      end
    end
  end

  private def render_newsletter_cta
    div class: "newsletter-cta" do
      h2 "Enjoyed this post?"
      para "Subscribe to our newsletter for more Crystal tutorials and updates."
      mount NewsletterSignupForm, inline: false, heading_level: 3
    end
  end

  private def format_date(date : Time?) : String
    return "Draft" unless date
    date.to_s("%B %-d, %Y")
  end
end
