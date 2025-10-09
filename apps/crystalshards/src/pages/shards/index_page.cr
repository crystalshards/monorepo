class Shards::IndexPage < MainLayout
  needs shards : Array(Shard)
  needs query : String?
  needs sort : String
  needs license : String?
  needs min_stars : Int32?
  needs has_docs : Bool?
  needs page : Int32
  needs per_page : Int32
  needs total_count : Int64

  def page_title
    @query ? "Search: #{@query}" : "Browse Shards"
  end

  def content
    section class: "section" do
      div class: "page-header" do
        h1 do
          text page_title
        end

        if @query
          para class: "search-results-count" do
            text "Found #{@total_count} shard#{@total_count == 1 ? "" : "s"}"
          end
        end
      end

      mount SearchBar, query: @query || ""

      render_filters_and_sorting

      if @shards.any?
        div class: "shard-list" do
          @shards.each do |shard|
            mount ShardCard, shard: shard
          end
        end

        render_pagination
      else
        div class: "empty-state" do
          para do
            text @query ? "No shards found matching your search." : "No shards available yet."
          end
          if @query || filters_active?
            a href: "/shards", class: "button" do
              text "Clear Filters"
            end
          end
        end
      end
    end
  end

  private def render_filters_and_sorting
    div class: "filters-section" do
      form action: "/shards", method: "get", class: "filters-form" do
        # Preserve search query
        if q = @query
          input type: "hidden", name: "query", value: q
        end

        div class: "filters-row" do
          # Sort dropdown
          div class: "filter-group" do
            label "Sort by:", for: "sort"
            tag "select", name: "sort", id: "sort", class: "filter-select" do
              tag "option", value: "updated", selected: @sort == "updated" do
                text "Recently Updated"
              end
              tag "option", value: "popular", selected: @sort == "popular" do
                text "Most Popular"
              end
              tag "option", value: "downloads", selected: @sort == "downloads" do
                text "Most Downloads"
              end
              tag "option", value: "name", selected: @sort == "name" do
                text "Name A-Z"
              end
            end
          end

          # License filter
          div class: "filter-group" do
            label "License:", for: "license"
            tag "select", name: "license", id: "license", class: "filter-select" do
              tag "option", value: "", selected: @license.nil? do
                text "All Licenses"
              end
              tag "option", value: "MIT", selected: @license == "MIT" do
                text "MIT"
              end
              tag "option", value: "Apache-2.0", selected: @license == "Apache-2.0" do
                text "Apache-2.0"
              end
              tag "option", value: "BSD-3-Clause", selected: @license == "BSD-3-Clause" do
                text "BSD-3-Clause"
              end
              tag "option", value: "GPL-3.0", selected: @license == "GPL-3.0" do
                text "GPL-3.0"
              end
            end
          end

          # Minimum stars filter
          div class: "filter-group" do
            label "Min Stars:", for: "min_stars"
            tag "select", name: "min_stars", id: "min_stars", class: "filter-select" do
              tag "option", value: "", selected: @min_stars.nil? do
                text "Any"
              end
              tag "option", value: "10", selected: @min_stars == 10 do
                text "10+"
              end
              tag "option", value: "50", selected: @min_stars == 50 do
                text "50+"
              end
              tag "option", value: "100", selected: @min_stars == 100 do
                text "100+"
              end
              tag "option", value: "500", selected: @min_stars == 500 do
                text "500+"
              end
            end
          end

          # Has documentation filter
          div class: "filter-group" do
            label do
              input(
                type: "checkbox",
                name: "has_docs",
                value: "true",
                checked: @has_docs == true
              )
              text " Has Documentation"
            end
          end

          # Apply filters button
          div class: "filter-group" do
            button type: "submit", class: "button button-primary" do
              text "Apply Filters"
            end
          end

          # Clear filters button
          if filters_active?
            div class: "filter-group" do
              a href: clear_filters_url, class: "button" do
                text "Clear Filters"
              end
            end
          end
        end
      end
    end
  end

  private def render_filters_and_sorting
    div class: "filters-section" do
      form action: "/shards", method: "get", class: "filters-form" do
        # Preserve search query
        if q = @query
          input type: "hidden", name: "query", value: q
        end

        div class: "filters-row" do
          # Sort dropdown
          div class: "filter-group" do
            label "Sort by:", for: "sort"
            tag "select", name: "sort", id: "sort", class: "filter-select" do
              tag "option", value: "updated", selected: @sort == "updated" do
                text "Recently Updated"
              end
              tag "option", value: "popular", selected: @sort == "popular" do
                text "Most Popular"
              end
              tag "option", value: "downloads", selected: @sort == "downloads" do
                text "Most Downloads"
              end
              tag "option", value: "name", selected: @sort == "name" do
                text "Name A-Z"
              end
            end
          end

          # License filter
          div class: "filter-group" do
            label "License:", for: "license"
            tag "select", name: "license", id: "license", class: "filter-select" do
              tag "option", value: "", selected: @license.nil? do
                text "All Licenses"
              end
              tag "option", value: "MIT", selected: @license == "MIT" do
                text "MIT"
              end
              tag "option", value: "Apache-2.0", selected: @license == "Apache-2.0" do
                text "Apache-2.0"
              end
              tag "option", value: "BSD-3-Clause", selected: @license == "BSD-3-Clause" do
                text "BSD-3-Clause"
              end
              tag "option", value: "GPL-3.0", selected: @license == "GPL-3.0" do
                text "GPL-3.0"
              end
            end
          end

          # Minimum stars filter
          div class: "filter-group" do
            label "Min Stars:", for: "min_stars"
            tag "select", name: "min_stars", id: "min_stars", class: "filter-select" do
              tag "option", value: "", selected: @min_stars.nil? do
                text "Any"
              end
              tag "option", value: "10", selected: @min_stars == 10 do
                text "10+"
              end
              tag "option", value: "50", selected: @min_stars == 50 do
                text "50+"
              end
              tag "option", value: "100", selected: @min_stars == 100 do
                text "100+"
              end
              tag "option", value: "500", selected: @min_stars == 500 do
                text "500+"
              end
            end
          end

          # Has documentation filter
          div class: "filter-group" do
            label do
              input(
                type: "checkbox",
                name: "has_docs",
                value: "true",
                checked: @has_docs == true
              )
              text " Has Documentation"
            end
          end

          # Apply filters button
          div class: "filter-group" do
            button type: "submit", class: "button button-primary" do
              text "Apply Filters"
            end
          end

          # Clear filters button
          if filters_active?
            div class: "filter-group" do
              a href: clear_filters_url, class: "button" do
                text "Clear Filters"
              end
            end
          end
        end
      end
    end
  end

  private def render_pagination
    total_pages = (@total_count.to_f / @per_page).ceil.to_i
    return if total_pages <= 1

    div class: "pagination" do
      if @page > 1
        a href: pagination_url(@page - 1), class: "pagination-link" do
          text "← Previous"
        end
      end

      span class: "pagination-info" do
        text "Page #{@page} of #{total_pages}"
      end

      if @page < total_pages
        a href: pagination_url(@page + 1), class: "pagination-link" do
          text "Next →"
        end
      end
    end
  end

  private def pagination_url(page : Int32) : String
    build_url(page: page)
  end

  private def clear_filters_url : String
    if q = @query
      "/shards?query=#{q}"
    else
      "/shards"
    end
  end

  private def build_url(page : Int32? = nil) : String
    params = [] of String
    params << "page=#{page || @page}"

    if q = @query
      params << "query=#{q}"
    end

    params << "sort=#{@sort}" unless @sort == "updated"

    if lic = @license
      params << "license=#{lic}"
    end

    if stars = @min_stars
      params << "min_stars=#{stars}"
    end

    params << "has_docs=true" if @has_docs
    "/shards?" + params.join("&")
  end

  private def filters_active? : Bool
    !@license.nil? || !@min_stars.nil? || @has_docs == true || @sort != "updated"
  end
end
