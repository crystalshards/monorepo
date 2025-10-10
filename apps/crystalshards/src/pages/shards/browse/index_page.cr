class Shards::Browse::IndexPage < MainLayout
  needs shards : Array(Shard)
  needs query : String?
  needs license : String?
  needs min_stars : Int32?
  needs sort : String
  needs direction : String
  needs page : Int32
  needs total_pages : Int32
  needs total_count : Int64

  def page_title
    "Browse Shards"
  end

  def content
    section class: "browse-section" do
      div class: "browse-header" do
        h1 do
          text "Browse Shards"
        end

        para class: "browse-subtitle" do
          text "Explore #{@total_count} Crystal packages"
        end
      end

      div class: "browse-container" do
        render_sidebar
        render_main_content
      end
    end
  end

  private def render_sidebar
    aside class: "browse-sidebar" do
      div class: "sidebar-section" do
        h3 do
          text "Search"
        end

        mount SearchBar, query: @query || "", placeholder: "Search shards..."
      end

      div class: "sidebar-section" do
        h3 do
          text "Filters"
        end

        form action: "/shards", method: "get", class: "filter-form" do
          if q = @query
            input type: "hidden", name: "query", value: q
          end

          div class: "filter-group" do
            label for: "license" do
              text "License"
            end

            tag "select", name: "license", id: "license", class: "filter-select" do
              tag "option", value: "", selected: @license.nil? do
                text "All Licenses"
              end

              ["MIT", "Apache-2.0", "BSD-3-Clause", "GPL-3.0", "ISC"].each do |lic|
                tag "option", value: lic, selected: @license == lic do
                  text lic
                end
              end
            end
          end

          div class: "filter-group" do
            label for: "min_stars" do
              text "Minimum Stars"
            end

            input(
              type: "number",
              name: "min_stars",
              id: "min_stars",
              value: @min_stars.try(&.to_s) || "",
              placeholder: "0",
              min: "0",
              class: "filter-input"
            )
          end

          div class: "filter-actions" do
            button type: "submit", class: "btn-primary" do
              text "Apply Filters"
            end

            if @query || @license || @min_stars
              a href: "/shards", class: "btn-secondary" do
                text "Clear All"
              end
            end
          end
        end
      end

      div class: "sidebar-section" do
        h3 do
          text "Sort By"
        end

        render_sort_links
      end
    end
  end

  private def render_sort_links
    div class: "sort-links" do
      [
        {"name", "Name"},
        {"downloads", "Downloads"},
        {"stars", "Stars"},
        {"updated", "Recently Updated"},
      ].each do |value, label|
        render_sort_link(value, label)
      end
    end
  end

  private def render_sort_link(value : String, label : String)
    is_active = @sort == value
    new_direction = if is_active
                      @direction == "asc" ? "desc" : "asc"
                    else
                      "desc"
                    end

    params = build_params(sort: value, direction: new_direction, page: 1)

    a href: "/shards?#{params}", class: sort_link_classes(is_active) do
      text label

      if is_active
        text " "
        span class: "sort-indicator" do
          text @direction == "asc" ? "↑" : "↓"
        end
      end
    end
  end

  private def sort_link_classes(active : Bool) : String
    classes = ["sort-link"]
    classes << "sort-link-active" if active
    classes.join(" ")
  end

  private def render_main_content
    div class: "browse-main" do
      render_results_header

      if @shards.any?
        div class: "shard-list" do
          @shards.each do |shard|
            mount ShardCard, shard: shard
          end
        end

        render_pagination
      else
        render_empty_state
      end
    end
  end

  private def render_results_header
    div class: "results-header" do
      para class: "results-count" do
        if @query
          text "Found #{@total_count} shards matching \"#{@query}\""
        else
          text "Showing #{@shards.size} of #{@total_count} shards"
        end
      end
    end
  end

  private def render_pagination
    return if @total_pages <= 1

    nav class: "pagination", aria_label: "Pagination" do
      if @page > 1
        a href: "/shards?#{build_params(page: @page - 1)}", class: "pagination-link" do
          text "← Previous"
        end
      end

      div class: "pagination-pages" do
        render_page_numbers
      end

      if @page < @total_pages
        a href: "/shards?#{build_params(page: @page + 1)}", class: "pagination-link" do
          text "Next →"
        end
      end
    end
  end

  private def render_page_numbers
    start_page = [@page - 2, 1].max
    end_page = [start_page + 4, @total_pages].min
    start_page = [end_page - 4, 1].max if end_page - start_page < 4

    if start_page > 1
      a href: "/shards?#{build_params(page: 1)}", class: "pagination-number" do
        text "1"
      end

      if start_page > 2
        span class: "pagination-ellipsis" do
          text "..."
        end
      end
    end

    (start_page..end_page).each do |page_num|
      if page_num == @page
        span class: "pagination-number pagination-number-active" do
          text page_num.to_s
        end
      else
        a href: "/shards?#{build_params(page: page_num)}", class: "pagination-number" do
          text page_num.to_s
        end
      end
    end

    if end_page < @total_pages
      if end_page < @total_pages - 1
        span class: "pagination-ellipsis" do
          text "..."
        end
      end

      a href: "/shards?#{build_params(page: @total_pages)}", class: "pagination-number" do
        text @total_pages.to_s
      end
    end
  end

  private def render_empty_state
    div class: "empty-state" do
      h2 do
        text "No shards found"
      end

      para do
        if @query
          text "No shards match your search for \"#{@query}\"."
        else
          text "No shards match your filters."
        end
      end

      a href: "/shards", class: "btn-primary" do
        text "Clear Filters"
      end
    end
  end

  private def build_params(**overrides) : String
    params = {} of String => String

    params["query"] = @query.to_s if @query
    params["license"] = @license.to_s if @license
    params["min_stars"] = @min_stars.to_s if @min_stars
    params["sort"] = @sort
    params["direction"] = @direction
    params["page"] = @page.to_s

    overrides.each do |key, value|
      params[key.to_s] = value.to_s
    end

    params.map { |k, v| "#{k}=#{URI.encode_www_form(v)}" }.join("&")
  end
end
