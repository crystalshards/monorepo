class Header < Lucky::BaseComponent
  # Search sits in the masthead, not in a landing hero. Finding a package is
  # the primary job of a registry, so it is reachable from every page and near
  # the top of the tab order rather than 574px down a marketing block. Hex and
  # RubyGems both do this; our previous landing pushed it below the fold.
  needs query : String = ""

  def render
    header class: "site-header" do
      nav class: "navbar", "aria-label": "Primary" do
        div class: "navbar-brand" do
          a href: "/", class: "logo" do
            text "CrystalShards"
          end
        end

        mount SearchBar, query: @query, field_id: "masthead-search", compact: true

        div class: "navbar-menu" do
          a href: "/shards", class: "nav-link" do
            text "Browse"
          end
          a href: "/stats", class: "nav-link" do
            text "Stats"
          end
          a href: "https://crystaldocs.org", class: "nav-link", target: "_blank", rel: "noopener" do
            text "Documentation"
          end
          a href: "/api/health", class: "nav-link" do
            text "API"
          end
        end
      end
    end
  end
end
