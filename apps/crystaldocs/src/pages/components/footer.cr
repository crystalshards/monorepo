class Components::Footer < Lucky::BaseComponent
  def render
    footer class: "site-footer" do
      div class: "container" do
        para do
          text "CrystalDocs.org - Crystal Shard Documentation Hosting"
        end
        div class: "footer-links" do
          a "GitHub", href: "https://github.com/crystalshards"
          text " | "
          a "CrystalShards", href: "https://crystalshards.org"
          text " | "
          a "Crystal Language", href: "https://crystal-lang.org"
        end
      end
    end
  end
end
