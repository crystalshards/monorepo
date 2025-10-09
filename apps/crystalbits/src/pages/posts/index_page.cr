class Posts::IndexPage < MainLayout
  needs posts : PostQuery
  needs current_page : Int32
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
    div class: "pagination" do
      if @current_page > 1
        a href: "/posts?page=#{@current_page - 1}", class: "pagination-link" do
          text "← Previous"
        end
      end

      span class: "pagination-current" do
        text "Page #{@current_page}"
      end

      a href: "/posts?page=#{@current_page + 1}", class: "pagination-link" do
        text "Next →"
      end
    end
  end
end
