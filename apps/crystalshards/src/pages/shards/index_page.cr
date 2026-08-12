class Shards::IndexPage < MainLayout
  needs shards : Array(Shard)
  # Counted once for the whole page by the action. Cards never resolve their
  # own, which is what keeps a listing at a fixed number of queries.
  needs dependent_counts : Hash(Int64, Int32)
  needs query : String?
  needs sort : String
  needs license : String?
  needs min_stars : Int32?
  needs has_docs : Bool?
  needs page : Int32
  needs per_page : Int32
  needs total_count : Int64

  # The sort the action falls back to, and the one the URL leaves implicit.
  DEFAULT_SORT = "popular"

  # Every sort the listing offers, in the order they appear in the dropdown.
  # There is no "downloads" entry: nothing is downloaded from this registry, so
  # that ordering could only ever have shuffled the list.
  SORT_OPTIONS = [
    {"popular", "Most Popular"},
    {"dependents", "Most Depended On"},
    {"stars", "Most Stars"},
    {"updated", "Recently Updated"},
    {"name", "Name A-Z"},
  ]

  LICENSE_OPTIONS = ["MIT", "Apache-2.0", "BSD-3-Clause", "GPL-3.0"]

  MIN_STAR_OPTIONS = [10, 50, 100, 500]

  def page_title
    @query ? "Search: #{@query}" : "Browse Shards"
  end

  def content
    section class: "section" do
      div class: "page-header" do
        h1 do
          text page_title
        end

        if q = @query
          para class: "search-results-count" do
            text "Found #{@total_count} shard#{@total_count == 1 ? "" : "s"} matching "
            strong do
              text q
            end
          end
        end
      end

      # Search lives in the masthead now, so there is no second field here.

      render_filters_and_sorting

      if @shards.any?
        div class: "shard-list" do
          @shards.each do |shard|
            mount ShardCard,
              shard: shard,
              dependent_count: @dependent_counts.fetch(shard.id, 0)
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
              text "View All Shards"
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
          div class: "filter-group" do
            label "Sort by:", for: "sort"
            tag "select", name: "sort", id: "sort", class: "filter-select" do
              SORT_OPTIONS.each do |value, caption|
                tag "option", value: value, selected: @sort == value do
                  text caption
                end
              end
            end
          end

          div class: "filter-group" do
            label "License:", for: "license"
            tag "select", name: "license", id: "license", class: "filter-select" do
              tag "option", value: "", selected: @license.nil? do
                text "All Licenses"
              end
              LICENSE_OPTIONS.each do |value|
                tag "option", value: value, selected: @license == value do
                  text value
                end
              end
            end
          end

          # Filtering on a minimum star count excludes shards whose stars have
          # never been fetched, because "at least 10 stars" is a claim we
          # cannot make about a shard we have not measured.
          div class: "filter-group" do
            label "Min Stars:", for: "min_stars"
            tag "select", name: "min_stars", id: "min_stars", class: "filter-select" do
              tag "option", value: "", selected: @min_stars.nil? do
                text "Any"
              end
              MIN_STAR_OPTIONS.each do |value|
                tag "option", value: value.to_s, selected: @min_stars == value do
                  text "#{value}+"
                end
              end
            end
          end

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

          div class: "filter-group" do
            button type: "submit", class: "button button-primary" do
              text "Apply Filters"
            end
          end

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

    params << "sort=#{@sort}" unless @sort == DEFAULT_SORT

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
    !@license.nil? || !@min_stars.nil? || @has_docs == true || @sort != DEFAULT_SORT
  end
end
