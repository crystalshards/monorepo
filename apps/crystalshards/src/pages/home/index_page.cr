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
        h1 class: "hero-title" do
          text "CrystalShards"
        end

        para class: "hero-subtitle" do
          text "The official package registry for the Crystal programming language"
        end

        mount SearchBar, large: true

        div class: "hero-stats" do
          div class: "stat" do
            strong do
              text @total_shards.to_s
            end
            text " shards"
          end
          div class: "stat" do
            strong do
              text format_number(@total_downloads)
            end
            text " downloads"
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
            mount ShardCard, shard: shard
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
            mount ShardCard, shard: shard
          end
        end

        div class: "section-footer" do
          a href: "/shards", class: "view-all-link" do
            text "View All Shards →"
          end
        end
      end
    end
  end

  private def format_number(num : Int64) : String
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
  end
end
