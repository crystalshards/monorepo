class Shards::IndexPage < MainLayout
  needs shards : Array(Shard)
  needs query : String?
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
          if @query
            a href: "/shards", class: "button" do
              text "View All Shards"
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
    params = [] of String
    params << "page=#{page}"
    params << "query=#{@query}" if @query
    "/shards?" + params.join("&")
  end
end
