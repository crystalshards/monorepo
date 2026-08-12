class Docs::IndexPage < MainLayout
  needs entries : Array(CrystalDocs::PackageCatalogue::Entry)
  # False when the registry could not be reached. The page then reports that it
  # cannot list the catalogue, rather than listing the packages this app
  # happens to hold and letting a fraction of the ecosystem read as all of it.
  needs available : Bool
  needs query : String?
  needs page : Int32
  needs per_page : Int32
  needs total_count : Int64

  def page_title
    query ? "Search: #{query}" : "Browse Documentation"
  end

  def content
    render_page_header

    if available?
      render_docs_list
      render_pagination
    else
      render_unavailable
    end
  end

  private def render_page_header
    div class: "page-header" do
      h1 page_title

      # Search itself lives in the masthead; here we only report what the
      # current query matched.
      if query && available?
        para class: "search-results-count" do
          text "Found #{total_count} package#{"s" unless total_count == 1} matching "
          strong query.to_s
        end
      end
    end
  end

  private def render_docs_list
    if entries.any?
      div class: "doc-list" do
        entries.each do |entry|
          mount Components::DocCard, entry: entry, heading_level: 2
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
        para "No packages are indexed yet"
      end
    end
  end

  # An outage is reported as an outage. The alternative is a page that answers
  # a question the reader did not ask with a number that looks like the one
  # they wanted.
  private def render_unavailable
    div class: "empty-state" do
      para "The shard index is unavailable right now, so this page cannot " \
           "list packages. Documentation already built is still served."
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
