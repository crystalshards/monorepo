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
        div do
          para class: "eyebrow" do
            text "Crystal shard documentation hosting"
          end

          h1 class: "hero-title" do
            text "Crystal"
            span class: "accent" do
              text "Docs"
            end
          end

          para class: "hero-subtitle" do
            text "Generated API documentation for every published shard, " \
                 "served straight from the source repository."
          end

          mount Components::SearchBar, query: nil, large: true, field_id: "hero-search"
        end

        tag "figure", class: "hero-figure" do
          img(
            src: asset("img/specimen-quartz.webp"),
            srcset: "#{asset("img/specimen-quartz.webp")} 560w, #{asset("img/specimen-quartz@2x.webp")} 1120w",
            sizes: "(max-width: 60rem) 22rem, 34rem",
            width: "560", height: "700",
            alt: "A clear quartz crystal point with a faceted, pyramidal tip, photographed on a light studio backdrop"
          )
          tag "figcaption" do
            text "Fig. 1 - Quartz, trigonal system"
          end
        end
      end

      div class: "hero-stats" do
        div class: "stat" do
          strong do
            text total_packages.to_s
          end
          span do
            text "Packages"
          end
        end
        div class: "stat" do
          strong do
            text total_versions.to_s
          end
          span do
            text "Versions"
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
            mount Components::DocCard, doc: doc, heading_level: 3
          end
        end
      else
        render_empty_state("No documentation available yet")
      end

      div class: "section-footer" do
        a href: "/docs", class: "view-all-link" do
          text "View All Documentation"
          tag "i", class: "fa-solid fa-arrow-right", "aria-hidden": "true"
        end
      end
    end
  end

  private def render_popular_docs
    section class: "section" do
      h2 "Popular Packages"

      if popular_docs.any?
        div class: "doc-grid" do
          popular_docs.each do |doc|
            mount Components::DocCard, doc: doc, heading_level: 3
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
