class Home::IndexPage < MainLayout
  needs total_packages : Int64
  needs total_versions : Int64
  needs recent_docs : DocQuery
  needs popular_docs : DocQuery

  def page_title
    "Crystal Shard Documentation"
  end

  def content
    render_hero
    render_recent_docs
    render_popular_docs
  end

  private def render_hero
    section class: "hero" do
      div class: "hero-content" do
        h1 "CrystalDocs", class: "hero-title"
        para "Crystal Shard Documentation Hosting", class: "hero-subtitle"

        mount Components::SearchBar, query: nil, large: true

        div class: "hero-stats" do
          div class: "stat" do
            strong total_packages.to_s
            text " Packages"
          end
          div class: "stat" do
            strong total_versions.to_s
            text " Versions"
          end
        end
      end
    end
  end

  private def render_recent_docs
    section class: "section" do
      h2 "Recently Updated"

      if recent_docs.any?
        div class: "doc-grid" do
          recent_docs.each do |doc|
            mount Components::DocCard, doc: doc
          end
        end
      else
        render_empty_state("No documentation available yet")
      end

      div class: "section-footer" do
        a "View All Documentation", href: "/docs", class: "view-all-link"
      end
    end
  end

  private def render_popular_docs
    section class: "section" do
      h2 "Popular Packages"

      if popular_docs.any?
        div class: "doc-grid" do
          popular_docs.each do |doc|
            mount Components::DocCard, doc: doc
          end
        end
      else
        render_empty_state("No documentation available yet")
      end
    end
  end

  private def render_empty_state(message : String)
    div class: "empty-state" do
      para message
    end
  end
end
