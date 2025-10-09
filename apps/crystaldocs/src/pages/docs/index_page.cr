class Docs::IndexPage < MainLayout
  needs docs : DocQuery
  needs query : String?
  needs page : Int32
  needs per_page : Int32
  needs total_count : Int64

  def page_title
    query ? "Search: #{query}" : "Browse Documentation"
  end

  def content
    render_page_header
    render_docs_list
    render_pagination
  end

  private def render_page_header
    div class: "page-header" do
      h1 page_title

      mount Components::SearchBar, query: query

      if query
        para class: "search-results-count" do
          text "Found #{total_count} package#{"s" unless total_count == 1}"
        end
      end
    end
  end

  private def render_docs_list
    if docs.any?
      div class: "doc-list" do
        docs.each do |doc|
          mount Components::DocCard, doc: doc
        end
      end
    else
      render_empty_state
    end
  end

  private def render_empty_state
    div class: "empty-state" do
      if query
        para "No packages found matching \"#{query}\""
        a "View all packages", href: "/docs", class: "button"
      else
        para "No documentation available yet"
      end
    end
  end

  private def render_pagination
    total_pages = (total_count.to_f / per_page).ceil.to_i
    return if total_pages <= 1

    div class: "pagination" do
      if page > 1
        a "Previous", href: docs_path(page - 1), class: "pagination-link"
      end

      span "Page #{page} of #{total_pages}", class: "pagination-info"

      if page < total_pages
        a "Next", href: docs_path(page + 1), class: "pagination-link"
      end
    end
  end

  private def docs_path(target_page : Int32) : String
    if query
      "/docs?query=#{URI.encode_www_form(query.to_s)}&page=#{target_page}"
    else
      "/docs?page=#{target_page}"
    end
  end
end
