class Posts::IndexPage < MainLayout
  needs posts : Array(Post)
  needs current_page : Int32
  needs per_page : Int32
  needs total_count : Int64
  needs tag : String?
  needs search : String?

  def page_title
    if @tag
      "Posts tagged '#{@tag}'"
    elsif @search
      "Search results for '#{@search}'"
    else
      "All Posts"
    end
  end

  def content
    section class: "posts-section" do
      render_header
      render_search_form
      render_posts
    end
  end

  private def render_header
    div class: "posts-header" do
      h1 do
        text page_title
      end
    end
  end

  private def render_search_form
    div class: "search-form" do
      form method: "get", action: "/posts" do
        if search_value = @search
          tag "input", type: "text", name: "search", placeholder: "Search posts...", value: search_value, class: "search-input"
        else
          tag "input", type: "text", name: "search", placeholder: "Search posts...", class: "search-input"
        end

        button type: "submit", class: "search-button" do
          text "Search"
        end
      end
    end
  end

  private def render_posts
    div class: "posts-list" do
      @posts.each do |post|
        mount PostCard, post: post, show_excerpt: true
      end
    end

    render_pagination if @posts.any?
  end

  private def render_pagination
    total_pages = (@total_count.to_f / @per_page).ceil.to_i

    return if total_pages <= 1

    div class: "pagination" do
      if @current_page > 1
        a href: build_pagination_url(@current_page - 1), class: "pagination-link" do
          text "← Previous"
        end
      end

      span class: "pagination-current" do
        text "Page #{@current_page} of #{total_pages}"
      end

      if @current_page < total_pages
        a href: build_pagination_url(@current_page + 1), class: "pagination-link" do
          text "Next →"
        end
      end
    end
  end

  private def build_pagination_url(page : Int32) : String
    params = [] of String
    params << "page=#{page}"
    params << "search=#{@search}" if @search
    params << "tag=#{@tag}" if @tag
    "/posts?#{params.join("&")}"
  end
end
