class Home::IndexPage < MainLayout
  needs featured_shards : Array(Shard)
  needs recent_shards : Array(Shard)
  needs total_shards : Int64
  needs total_downloads : Int64

  def page_title
    "Home"
  end

  def content
    section class: "hero" do
      div class: "hero-content" do
        div do
          para class: "eyebrow" do
            text "The Crystal package registry"
          end

          h1 class: "hero-title" do
            text "Every shard, cut and "
            span class: "accent" do
              text "catalogued"
            end
            text "."
          end

          para class: "hero-subtitle" do
            text "Versions, dependencies and generated API documentation, " \
                 "indexed straight from the source repository."
          end

          mount SearchBar, large: true, field_id: "hero-search"
        end

        tag "figure", class: "hero-figure" do
          img(
            src: asset("img/specimen-beryl.webp"),
            srcset: "#{asset("img/specimen-beryl.webp")} 560w, #{asset("img/specimen-beryl@2x.webp")} 1120w",
            sizes: "(max-width: 60rem) 22rem, 34rem",
            width: "560", height: "700",
            alt: "A faceted beryl crystal specimen lit to catch each cut plane"
          )
          tag "figcaption" do
            text "Fig. 1 - Beryl, hexagonal system"
          end
        end
      end

      div class: "hero-stats" do
        div class: "stat" do
          strong do
            text @total_shards.to_s
          end
          span do
            text "Shards"
          end
        end
        div class: "stat" do
          strong do
            text format_number(@total_downloads)
          end
          span do
            text "Downloads"
          end
        end
      end
    end

    if @featured_shards.any?
      section class: "section" do
        h2 do
          text "Featured Shards"
        end

        div class: "shard-grid" do
          @featured_shards.each do |shard|
            mount ShardCard, shard: shard, heading_level: 3
          end
        end
      end
    end

    if @recent_shards.any?
      section class: "section" do
        h2 do
          text "Recently Updated"
        end

        div class: "shard-grid" do
          @recent_shards.each do |shard|
            mount ShardCard, shard: shard, heading_level: 3
          end
        end

        div class: "section-footer" do
          a href: "/shards", class: "view-all-link" do
            text "View All Shards"
            tag "i", class: "fa-solid fa-arrow-right", "aria-hidden": "true"
          end
        end
      end
    end
  end

  private def format_number(num : Int64) : String
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
  end
end
