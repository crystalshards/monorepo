class Header < Lucky::BaseComponent
  # Search belongs in the masthead so it works from any page, rather than
  # only existing on the posts index.
  needs query : String = ""

  def render
    header class: "site-header" do
      nav class: "navbar", "aria-label": "Primary" do
        div class: "navbar-brand" do
          a href: "/", class: "logo" do
            text "CrystalBits"
          end
        end

        mount SearchBar, query: @query, field_id: "masthead-search", compact: true

        div class: "navbar-menu" do
          a href: "/posts", class: "nav-link" do
            text "All Posts"
          end
          a href: "https://crystalshards.org", class: "nav-link", target: "_blank", rel: "noopener" do
            text "CrystalShards"
          end
          a href: "https://crystaldocs.org", class: "nav-link", target: "_blank", rel: "noopener" do
            text "Documentation"
          end
        end
      end
    end
  end
end
