class Components::Header < Lucky::BaseComponent
  # Search sits in the masthead, not in a landing hero. Finding the docs for
  # a package is the primary job of a documentation host, so it is reachable
  # from every page and near the top of the tab order rather than down a
  # marketing block. Hex and RubyGems both do this.
  needs query : String? = nil

  def render
    header class: "site-header" do
      nav class: "navbar", "aria-label": "Primary" do
        div class: "navbar-brand" do
          a href: "/", class: "logo" do
            text "CrystalDocs"
          end
        end

        mount Components::SearchBar, query: query, field_id: "masthead-search", compact: true

        div class: "navbar-menu" do
          a "Browse Docs", href: "/docs", class: "nav-link"
          a "CrystalShards", href: "https://crystalshards.org", class: "nav-link"
          a "About", href: "/about", class: "nav-link"
        end
      end
    end
  end
end
