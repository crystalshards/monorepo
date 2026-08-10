class Home::IndexPage < MainLayout
  needs total_packages : Int64
  needs total_versions : Int64
  needs recent_docs : DocQuery
  needs popular_docs : DocQuery

  def page_title
    "Crystal Shard Documentation"
  end

  # The landing page of a documentation host exists to get someone to the
  # docs they need. Search lives in the masthead, so the page itself leads
  # with what you actually do next: pin a version, deep-link a type, publish
  # your own. There is no hero image; a decorative photograph pushed the
  # documentation a full screen further down.
  def content
    render_intro
    render_recipes
    render_recent_docs
    render_popular_docs
  end

  private def render_intro
    section class: "intro" do
      div class: "intro-copy" do
        h1 class: "intro-title" do
          text "Documentation for every "
          span class: "accent" do
            text "Crystal shard"
          end
        end

        para class: "intro-lede" do
          text "Generated API documentation for every published shard, " \
               "served straight from the source repository."
        end
      end

      dl class: "intro-stats" do
        div do
          tag "dt" do
            text "Packages"
          end
          tag "dd" do
            text format_number(total_packages)
          end
        end
        div do
          tag "dt" do
            text "Versions"
          end
          tag "dd" do
            text format_number(total_versions)
          end
        end
      end
    end
  end

  # The fastest path from landing to reading docs is the exact URL you paste
  # or the exact command you run, so each card is copy-pasteable.
  private def render_recipes
    section class: "section" do
      h2 class: "visually-hidden" do
        text "Using CrystalDocs"
      end

      div class: "recipe-grid" do
        recipe(
          "Pin a version",
          "The version in the path is the version you read. Omit it and you follow the current release.",
          "https://crystaldocs.org/docs/kemal/1.6.0"
        )
        recipe(
          "Link a type or method",
          "Types are files below the version, and namespaces nest. Methods are anchors on the type page, like #size-instance-method.",
          "https://crystaldocs.org/docs/kemal/1.6.0/Kemal/Config.html"
        )
        recipe(
          "Publish your docs",
          "Tag a release on the repository and the builder picks it up. There is nothing to upload.",
          "git tag -a v1.0.0 -m \"Release v1.0.0\"\ngit push --tags"
        )
      end
    end
  end

  private def recipe(title : String, blurb : String, snippet : String)
    article class: "recipe" do
      h3 do
        text title
      end
      para do
        text blurb
      end
      div class: "code-block" do
        pre do
          code do
            text snippet
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

  private def format_number(number : Int64) : String
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
  end
end
