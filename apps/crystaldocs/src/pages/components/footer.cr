class Components::Footer < Lucky::BaseComponent
  def render
    footer class: "site-footer" do
      div class: "container" do
        para do
          text "CrystalDocs.org - Crystal Shard Documentation Hosting"
        end
        div class: "footer-links" do
          a "GitHub", href: "https://github.com/crystalshards"
          a "CrystalShards", href: "https://crystalshards.org"
          a "Crystal Language", href: "https://crystal-lang.org"
        end
      end
    end
  end
end
