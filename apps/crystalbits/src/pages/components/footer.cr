class Footer < Lucky::BaseComponent
  def render
    footer class: "site-footer" do
      div class: "container" do
        div class: "footer-content" do
          div class: "footer-section" do
            h3 "CrystalBits"
            para "News, tutorials, and updates from the Crystal community."
          end

          div class: "footer-section" do
            h3 "Quick Links"
            ul class: "footer-links" do
              li { a href: "/" do
                text "Home"
              end }
              li { a href: "/posts" do
                text "All Posts"
              end }
              # Internal, so no target=_blank: what this site is read for is
              # part of the site rather than a reference out of it.
              li { a href: "/stats" do
                text "Stats"
              end }
              render_site_links
            end
          end

          div class: "footer-section" do
            h3 "Newsletter"
            para "Stay updated with the latest Crystal news and tutorials."
            mount NewsletterSignupForm, inline: true, field_id: "newsletter-email-footer"
          end
        end

        div class: "footer-bottom" do
          para "© #{Time.utc.year} CrystalBits. Part of the Crystal ecosystem."
          render_bushido_line
        end
      end
    end
  end

  # The other three Bushido Collective sites, from configuration rather than
  # a hardcoded hostname: SiteLinks reads each one's real origin, so this
  # link can never point at another environment's copy of a sibling site.
  #
  # rel=noopener goes with every target=_blank: without it the opened page
  # can reach back through window.opener.
  private def render_site_links
    SiteLinks.others(than: :crystalbits).each do |site|
      entry = SiteLinks::SITES[site]
      li do
        a href: SiteLinks.origin(site), title: entry.description, target: "_blank", rel: "noopener" do
          text entry.name
        end
      end
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
      span class: "tbc-seal-copy" do
        text "The Bushido Collective builds and maintains this site."
        br
        text "Licensed under the "
        a "Apache License 2.0", href: "https://github.com/crystalshards/monorepo/blob/main/LICENSE",
          target: "_blank", rel: "noopener"
      end
    end
  end
end
