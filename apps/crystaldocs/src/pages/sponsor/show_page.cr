class Sponsor::ShowPage < MainLayout
  def page_title
    "Sponsor"
  end

  # The ask comes after the case for it: what the site does, what running it
  # costs, what the money cannot buy, and who is asking. Only then the
  # button, and only when there is a real destination behind it.
  def content
    render_intro
    render_costs
    render_no_influence
    render_maintainer
    render_destination
  end

  private def render_intro
    section class: "intro" do
      div class: "intro-copy" do
        h1 class: "intro-title" do
          text "Open infrastructure has a "
          span class: "accent" do
            text "bill"
          end
        end

        para class: "intro-lede" do
          text "CrystalDocs builds and hosts API documentation for every " \
               "published Crystal shard, generated from the source of a " \
               "tagged release and rendered here, with scripting off. The " \
               "Bushido Collective maintains it and pays for it out of " \
               "pocket. Sponsorship covers the infrastructure bill."
        end
      end
    end
  end

  # No dollar figures: we do not quote numbers we have not been handed. Each
  # driver is named with the thing that makes it grow, which stays true after
  # any invoice goes stale.
  private def render_costs
    section class: "section" do
      div class: "section-head" do
        h2 do
          text "What the money pays for"
        end
      end

      div class: "sponsor-copy" do
        para do
          text "No invented figures. These are the real cost drivers, and " \
               "each one grows with the ecosystem rather than with our ambitions."
        end
      end

      ul class: "sponsor-costs" do
        cost_item "The build sandbox",
          "Every tagged release of every shard triggers a build: the Crystal " \
          "compiler's own documentation generator runs against that tag " \
          "inside a locked down job with no network and no credentials, " \
          "because a shard's macros can execute code at compile time. That " \
          "confinement is why these pages are safe to serve, it runs once " \
          "per release, and it is billed per run."
        cost_item "Storage",
          "Object storage keeps one machine-readable documentation build for " \
          "every version of every shard. Every tag anyone pushes adds one, " \
          "and none of them are deleted."
        cost_item "Compute",
          "The documentation host and its three sibling services run on " \
          "Cloud Run, metered by the request and by the CPU-second, so a " \
          "busier ecosystem costs more to serve."
        cost_item "The database",
          "Cloud SQL holds the build records and package metadata these " \
          "pages are rendered from. It is sized to stay fast as the archive " \
          "grows, not to be cheap on the day it was provisioned."
        cost_item "Bandwidth and the small print",
          "Serving documentation, plus DNS, logging and monitoring. " \
          "Individually small, never zero."
      end
    end
  end

  private def cost_item(name : String, blurb : String)
    li do
      strong do
        text "#{name}. "
      end
      text blurb
    end
  end

  # For a documentation host this is the whole credibility question, so it
  # gets its own section in plain words rather than a line of fine print. The
  # spec suite asserts this statement verbatim; soften it and the build goes
  # red.
  private def render_no_influence
    section class: "section" do
      div class: "section-head" do
        h2 do
          text "What sponsorship does not buy"
        end
      end

      div class: "sponsor-copy" do
        para do
          text "Sponsorship does not buy influence over what CrystalDocs " \
               "builds, hosts, or shows. Every tagged release gets the same " \
               "build, the same templates, and the same place in the URL " \
               "structure whether its author sponsors or not. Documentation " \
               "is not promoted, demoted, or reordered for money, and there " \
               "are no sponsored placements anywhere on the site, at any " \
               "tier. If that ever changes, it changes on this page first."
        end
      end
    end
  end

  # The collective is named and linked, with the same seal the footer
  # carries, because the alternative is asking money for a faceless
  # foundation. It is neither: it is the people who run the pager.
  private def render_maintainer
    section class: "section" do
      div class: "section-head" do
        h2 do
          text "Who you are paying"
        end
      end

      div class: "sponsor-copy" do
        para do
          text "CrystalDocs is built and maintained by The Bushido " \
               "Collective, the same small group of working engineers behind " \
               "CrystalShards, CrystalGigs and CrystalBits. It is not a " \
               "foundation and there is no staff: the people who write the " \
               "code are the people who answer the pager."
        end
        para class: "tbc-seal-line" do
          a href: "https://thebushido.co", class: "tbc-seal-link", target: "_blank",
            rel: "noopener", "aria-label": "Forged by The Bushido Collective" do
            span class: "tbc-seal", "aria-hidden": "true"
          end
          a "The Bushido Collective", href: "https://thebushido.co",
            target: "_blank", rel: "noopener"
        end
      end
    end
  end

  # The destination is configuration, not code. When it is set, this section
  # is the ask; when it is not, this section is the honest answer instead of
  # a button wired to nowhere.
  private def render_destination
    section class: "section" do
      div class: "section-head" do
        h2 do
          text "How to sponsor"
        end
      end

      div class: "sponsor-copy" do
        if destination = Sponsorship.destination
          para do
            text "Contributions are collected at "
            strong do
              text destination.host.to_s
            end
            text ", where you can also see how the money is used."
          end
          para do
            a "Become a sponsor", href: destination.to_s,
              class: "button button-primary", target: "_blank", rel: "noopener"
          end
        else
          para do
            text "Sponsorship is not open yet. We are still deciding where " \
                 "contributions should go, and when the decision is made " \
                 "this page is where the link will appear. Until then, the " \
                 "most useful thing you can do is read the documentation " \
                 "and publish shards worth documenting."
          end
        end
      end
    end
  end
end
