class Home::IndexPage < MainLayout
  needs featured_shards : Array(Shard)
  needs recent_shards : Array(Shard)
  needs dependent_counts : Hash(Int64, Int32)
  needs total_shards : Int64
  needs total_dependency_links : Int64
  needs total_stars : Int64
  needs shards_with_stars : Int32

  def page_title
    "Home"
  end

  # The landing page of a registry exists to get someone to a package. Search
  # lives in the masthead, so the page itself leads with what you actually do
  # next: add a dependency, then see what is here. There is no hero image;
  # a decorative photograph pushed the packages a full screen further down.
  def content
    render_intro
    render_getting_started
    render_shard_lists
    # Last, so nothing a reader came for waits on it. The strip renders
    # nothing at all when CrystalBits has nothing recent or cannot be
    # reached, so this line adds no markup on a bad day.
    mount BitsStrip
  end

  private def render_intro
    section class: "intro" do
      div class: "intro-copy" do
        h1 class: "intro-title" do
          text "The package registry for "
          span class: "accent" do
            text "Crystal"
          end
        end

        para class: "intro-lede" do
          text "Versions, dependencies and generated API documentation, " \
               "indexed straight from the source repository."
        end
      end

      # There is no downloads stat and there will not be one. Nothing is
      # downloaded from this registry, so the counter could only ever read
      # zero, and a permanent zero claims "nobody uses these" rather than
      # "we do not measure this".
      dl class: "intro-stats" do
        stat "Shards", format_number(@total_shards)

        # Stars are fetched from the host, so they can be genuinely unmeasured.
        # The stat says which it is instead of printing a zero that reads as a
        # verdict on the ecosystem.
        if @shards_with_stars.zero?
          stat "Stars", "not indexed yet", unknown: true
        else
          stat "Stars", format_number(@total_stars)
        end

        # Dependency links are computed from tables we own, so zero is a
        # measured fact and needs no unknown state.
        stat "Dependency links", format_number(@total_dependency_links)
      end
    end
  end

  # Lifted from what Hex does best: the fastest path from landing to using a
  # package is the exact line you paste into shard.yml.
  private def render_getting_started
    section class: "section" do
      h2 class: "visually-hidden" do
        text "Getting started"
      end

      div class: "recipe-grid" do
        recipe(
          "Add a dependency",
          "Declare it in shard.yml, then fetch it.",
          "dependencies:\n  kemal:\n    github: kemalcr/kemal\n    version: ~> 1.6.0"
        )
        recipe(
          "Install",
          "Resolves the tree and writes shard.lock.",
          "shards install"
        )
        recipe(
          "Publish",
          "Tag a release and the registry indexes it.",
          "git tag -a v1.0.0 -m \"Release\"\ngit push --tags"
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

  private def render_shard_lists
    if @featured_shards.any?
      section class: "section" do
        div class: "section-head" do
          h2 do
            text "Most starred"
          end
          span class: "rule"
        end

        div class: "shard-grid" do
          @featured_shards.each do |shard|
            mount ShardCard,
              shard: shard,
              heading_level: 3,
              dependent_count: @dependent_counts.fetch(shard.id, 0)
          end
        end
      end
    end

    if @recent_shards.any?
      section class: "section" do
        div class: "section-head" do
          h2 do
            text "Recently updated"
          end
          span class: "rule"
          a href: "/shards", class: "view-all-link" do
            text "All shards"
            tag "i", class: "fa-solid fa-arrow-right", "aria-hidden": "true"
          end
        end

        div class: "shard-grid" do
          @recent_shards.each do |shard|
            mount ShardCard,
              shard: shard,
              heading_level: 3,
              dependent_count: @dependent_counts.fetch(shard.id, 0)
          end
        end
      end
    end
  end

  private def stat(label : String, value : String, unknown : Bool = false)
    div do
      tag "dt" do
        text label
      end
      tag "dd", class: unknown ? "stat-unknown" : "" do
        text value
      end
    end
  end

  private def format_number(number : Int64) : String
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
  end
end
