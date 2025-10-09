class Footer < Lucky::BaseComponent
  def render
    footer class: "site-footer" do
      div class: "container" do
        para do
          text "CrystalShards.org - The Crystal Language Package Registry"
        end
        para class: "footer-links" do
          a href: "https://github.com/crystalshards", target: "_blank" do
            text "GitHub"
          end
          text " | "
          a href: "/api", target: "_blank" do
            text "API"
          end
        end
      end
    end
  end
end
