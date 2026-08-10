class Components::Header < Lucky::BaseComponent
  def render
    header class: "site-header" do
      nav class: "navbar", "aria-label": "Primary" do
        div class: "navbar-brand" do
          a href: "/", class: "logo" do
            text "CrystalDocs"
          end
        end

        div class: "navbar-menu" do
          a "Browse Docs", href: "/docs", class: "nav-link"
          a "CrystalShards", href: "https://crystalshards.org", class: "nav-link"
          a "About", href: "/about", class: "nav-link"
        end
      end
    end
  end
end
