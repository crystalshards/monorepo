class Footer < Lucky::BaseComponent
  def render
    footer class: "site-footer" do
      div class: "container" do
        para do
          text "CrystalShards.org - The Crystal Language Package Registry"
        end
        # "API" used to sit here pointing at /api, which is not a route: it
        # returned a server error from every page on the site. The masthead
        # already links the live API endpoint, and an HTML API reference is
        # not something this app ships, so the slot carries the ecosystem
        # links the other three footers carry instead.
        #
        # rel=noopener goes with every target=_blank: without it the opened
        # page can reach back through window.opener.
        div class: "footer-links" do
          a "GitHub", href: "https://github.com/crystalshards", target: "_blank", rel: "noopener"
          a "CrystalDocs", href: "https://crystaldocs.org", target: "_blank", rel: "noopener"
          a "Crystal Language", href: "https://crystal-lang.org", target: "_blank", rel: "noopener"
        end
      end
    end
  end
end
