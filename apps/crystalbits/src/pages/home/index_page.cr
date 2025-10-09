class Home::IndexPage < MainLayout
  needs featured_post : Post?
  needs recent_posts : PostQuery

  def page_title
    "Home"
  end

  def content
    render_hero
    render_featured_post if @featured_post
    render_recent_posts
    render_newsletter_section
  end

  private def render_hero
    section class: "hero" do
      div class: "hero-content" do
        h1 "CrystalBits"
        para class: "hero-subtitle" do
          text "Tutorials, news, and insights from the Crystal programming language community"
        end
      end
    end
  end

  private def render_featured_post
    return unless post = @featured_post

    section class: "featured-section" do
      h2 "Featured Post"
      div class: "featured-post" do
        article class: "featured-article" do
          h3 class: "featured-title" do
            a href: "/posts/#{post.slug}" do
              text post.title
            end
          end

          div class: "post-meta" do
            span class: "post-author" do
              text "By #{post.author_name}"
            end
            span class: "post-separator" do
              text "•"
            end
            span class: "post-date" do
              text format_date(post.published_at)
            end
            span class: "post-separator" do
              text "•"
            end
            span class: "post-views" do
              text "#{post.view_count} views"
            end
          end

          if excerpt = post.excerpt
            para class: "featured-excerpt" do
              text excerpt
            end
          end

          a href: "/posts/#{post.slug}", class: "read-more" do
            text "Read More →"
          end
        end
      end
    end
  end

  private def render_recent_posts
    section class: "recent-posts-section" do
      h2 "Recent Posts"

      div class: "posts-grid" do
        @recent_posts.each do |post|
          mount PostCard, post: post, show_excerpt: true
        end
      end

      div class: "view-all" do
        a href: "/posts", class: "btn-primary" do
          text "View All Posts"
        end
      end
    end
  end

  private def render_newsletter_section
    section class: "newsletter-section" do
      mount NewsletterSignupForm, inline: false
    end
  end

  private def format_date(date : Time?) : String
    return "Draft" unless date
    date.to_s("%B %-d, %Y")
  end
end
