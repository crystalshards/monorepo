class News::IndexPage < MainLayout
  needs items : Array(ContentItem)
  needs origin : String?

  FILTERS = [
    {nil, "Everything"},
    {ContentItem::Origin::CONTRIBUTION, "Community"},
    {ContentItem::Origin::CRYSTAL_BLOG, "Crystal blog"},
    {ContentItem::Origin::GENERATED, "Machine-drafted"},
  ]

  def page_title
    case @origin
    when ContentItem::Origin::CONTRIBUTION then "Community contributions"
    when ContentItem::Origin::CRYSTAL_BLOG then "From the Crystal blog"
    when ContentItem::Origin::GENERATED    then "Machine-drafted news"
    else                                        "News"
    end
  end

  def content
    section class: "news-section" do
      render_header
      render_filters
      render_items
      render_sources_note
    end
  end

  private def render_header
    div class: "news-header" do
      h1 do
        text page_title
      end

      para class: "news-lede" do
        text "Crystal news from three places: what readers send us, what the " \
             "Crystal team publishes, and what we write ourselves when the " \
             "first two are quiet. Every item says which it is."
      end
    end
  end

  private def render_filters
    nav class: "news-filters", "aria-label": "Filter by source" do
      FILTERS.each do |value, label|
        current = value == @origin

        a href: value ? "/news?origin=#{value}" : "/news",
          class: current ? "news-filter news-filter-current" : "news-filter",
          "aria-current": current ? "page" : "false" do
          text label
        end
      end
    end
  end

  private def render_items
    if @items.empty?
      render_empty
    else
      div class: "news-list" do
        @items.each do |item|
          mount ContentItemCard, item: item, heading_level: 2
        end
      end
    end
  end

  # An empty index is a real state, not an error. Nothing is approved yet, and
  # saying so plainly beats an index that fills itself to look busy.
  private def render_empty
    div class: "news-empty" do
      para do
        text "Nothing approved here yet. Everything we publish is reviewed by a " \
             "person first, so this page stays empty until it has been."
      end

      a href: "/contribute", class: "btn-primary" do
        text "Contribute something"
      end
    end
  end

  private def render_sources_note
    footer class: "news-sources-note" do
      h2 "Where this comes from"

      ul do
        li do
          text "Community contributions, submitted through "
          a href: "/contribute" do
            text "the contribution form"
          end
          text " and published only after review."
        end

        li do
          text "Headlines and summaries from the official Crystal blog feed at "
          a href: CrystalBlogFeed::FEED_URL, rel: "noopener", target: "_blank" do
            text "crystal-lang.org/feed.xml"
          end
          text ". We link to the articles; we do not host them."
        end

        li do
          text "Items we write ourselves from public community discussion. " \
               "Those are labelled machine-drafted and list the threads they " \
               "were written from."
        end
      end
    end
  end
end
