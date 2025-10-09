class Header < Lucky::BaseComponent
  def render
    header class: "site-header" do
      nav class: "navbar" do
        div class: "navbar-brand" do
          a href: "/", class: "logo" do
            text "CrystalBits"
          end
        end

        div class: "navbar-menu" do
          a href: "/", class: "nav-link" do
            text "Home"
          end
          a href: "/posts", class: "nav-link" do
            text "All Posts"
          end
          a href: "https://crystalshards.org", class: "nav-link", target: "_blank" do
            text "CrystalShards"
          end
          a href: "https://crystaldocs.org", class: "nav-link", target: "_blank" do
            text "Documentation"
          end
        end
      end
    end
  end
end
