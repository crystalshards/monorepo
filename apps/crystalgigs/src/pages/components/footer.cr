class Footer < Lucky::BaseComponent
  def render
    footer class: "site-footer" do
      div class: "footer-content" do
        # Spans the full grid row above the link sections; its own CSS block
        # carries the width.
        mount NewsletterSignup

        div class: "footer-section" do
          h2 do
            text "CrystalGigs"
          end
          para do
            text "The premier job board for Crystal developers"
          end
        end

        div class: "footer-section" do
          h2 do
            text "For Job Seekers"
          end
          ul do
            li do
              a href: "/jobs" do
                text "Browse Jobs"
              end
            end
            li do
              a href: "/jobs?remote=true" do
                text "Remote Jobs"
              end
            end
            # Audience numbers only, which is why this sits with the job
            # seekers rather than the employers: it reports who reads the
            # board, never how any employer's posting performed.
            li do
              a href: "/stats" do
                text "Stats"
              end
            end
          end
        end

        div class: "footer-section" do
          h2 do
            text "For Employers"
          end
          ul do
            li do
              a href: "/jobs/new" do
                text "Post a Job"
              end
            end
            li do
              a href: "/pricing" do
                text "Pricing"
              end
            end
          end
        end

        div class: "footer-section" do
          h2 do
            text "Crystal Ecosystem"
          end
          ul do
            render_site_links
            li do
              # rel=noopener goes with every target=_blank: without it the
              # opened page can reach back through window.opener.
              a href: "https://crystal-lang.org", target: "_blank", rel: "noopener" do
                text "Crystal Language"
              end
            end
          end
        end
      end

      div class: "footer-bottom" do
        para do
          text "© #{Time.utc.year} CrystalGigs. Part of the Crystal ecosystem."
        end
        render_bushido_line
      end
    end
  end

  # The other three Bushido Collective sites, from configuration rather than
  # a hardcoded hostname: SiteLinks reads each one's real origin, so this
  # link can never point at another environment's copy of a sibling site.
  private def render_site_links
    SiteLinks.others(than: :crystalgigs).each do |site|
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
      text " The Bushido Collective builds and maintains this site."
      text " · Licensed under the "
      a "Apache License 2.0", href: "https://github.com/crystalshards/monorepo/blob/main/LICENSE",
        target: "_blank", rel: "noopener"
    end
  end
end
