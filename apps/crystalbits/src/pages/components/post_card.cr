class PostCard < Lucky::BaseComponent
  needs post : Post
  needs show_excerpt : Bool = true
  # Cards appear under an h1 on the posts index and under an h2 in homepage
  # sections, so the level is set by the caller rather than baked in.
  needs heading_level : Int32 = 2

  def render
    article class: "post-card" do
      div class: "post-header" do
        tag "h#{@heading_level}", class: "post-title" do
          a href: "/posts/#{@post.slug}" do
            text @post.title
          end
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

      if @show_excerpt && @post.excerpt
        para class: "post-excerpt" do
          text @post.excerpt.to_s
        end
      end

      unless @post.tags.empty?
        div class: "post-tags" do
          @post.tags.each do |tag|
            span class: "tag" do
              text tag
            end
          end
        end
      end
    end
  end

  private def format_date(date : Time?) : String
    return "Draft" unless date
    date.to_s("%B %-d, %Y")
  end
end
