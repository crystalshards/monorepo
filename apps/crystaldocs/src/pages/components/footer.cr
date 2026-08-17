class Components::Footer < Lucky::BaseComponent
  def render
    footer class: "site-footer" do
      div class: "container" do
        para do
          text "CrystalDocs.org - Crystal Shard Documentation Hosting"
        end
        mount Components::NewsletterSignup
        # rel=noopener goes with every target=_blank: without it the opened
        # page can reach back through window.opener.
        div class: "footer-links" do
          a "GitHub", href: "https://github.com/crystalshards", target: "_blank", rel: "noopener"
          render_site_links
          a "Crystal Language", href: "https://crystal-lang.org", target: "_blank", rel: "noopener"
          # Internal, so no target=_blank: the one link in this row that stays
          # on the site, because paying for it is part of the site.
          a "Sponsor", href: "/sponsor"
        end
        render_bushido_line
      end
    end
  end

  # The other three Bushido Collective sites, from configuration rather than
  # a hardcoded hostname: SiteLinks reads each one's real origin, so this
  # link can never point at another environment's copy of a sibling site.
  private def render_site_links
    SiteLinks.others(than: :crystaldocs).each do |site|
      entry = SiteLinks::SITES[site]
      a entry.name, href: SiteLinks.origin(site), title: entry.description,
        target: "_blank", rel: "noopener"
    end
  end

  # The collective's mark, a line naming it as this site's maintainer, and
  # this repository's license, sized and placed as a maker's mark rather
  # than a banner: .tbc-seal in app.css carries the currentColor treatment
  # and the size floor, not this markup.
  private def render_bushido_line
    para class: "tbc-seal-line" do
      a href: "https://thebushido.co", class: "tbc-seal-link", target: "_blank",
        rel: "noopener", "aria-label": "Forged by The Bushido Collective" do
        span class: "tbc-seal", "aria-hidden": "true"
      end
      text " The Bushido Collective builds and maintains this site."
      text " · Licensed under the "
      a "Apache License 2.0", href: "https://github.com/crystalshards/monorepo/blob/main/LICENSE",
        target: "_blank", rel: "noopener"
    end
  end
end
