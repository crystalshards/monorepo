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
        # links the other three footers carry instead: the sibling Bushido
        # Collective sites, then the language itself.
        #
        # rel=noopener goes with every target=_blank: without it the opened
        # page can reach back through window.opener.
        div class: "footer-links" do
          a "GitHub", href: "https://github.com/crystalshards", target: "_blank", rel: "noopener"
          render_site_links
          a "Crystal Language", href: "https://crystal-lang.org", target: "_blank", rel: "noopener"
        end
        render_bushido_line
      end
    end
  end

  # The other three Bushido Collective sites, from configuration rather than
  # a hardcoded hostname: SiteLinks reads each one's real origin, so this
  # link can never point at another environment's copy of a sibling site.
  private def render_site_links
    SiteLinks.others(than: :crystalshards).each do |site|
      entry = SiteLinks::SITES[site]
      a entry.name, href: SiteLinks.origin(site), title: entry.description,
        target: "_blank", rel: "noopener"
    end
  end

  # The collective's mark and this repository's license, sized and placed as
  # a maker's mark rather than a banner: .tbc-seal in app.css carries the
  # currentColor treatment and the size floor, not this markup.
  private def render_bushido_line
    para class: "tbc-seal-line" do
      a href: "https://thebushido.co", class: "tbc-seal-link", target: "_blank",
        rel: "noopener", "aria-label": "Forged by The Bushido Collective" do
        span class: "tbc-seal", "aria-hidden": "true"
      end
      text " · Licensed under the "
      a "Apache License 2.0", href: "https://github.com/crystalshards/monorepo/blob/main/LICENSE",
        target: "_blank", rel: "noopener"
    end
  end
end
