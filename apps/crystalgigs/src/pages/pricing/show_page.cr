class Pricing::ShowPage < MainLayout
  # One posting, one price, no tiers. A pricing page for a single-SKU product
  # should answer three questions and stop: what it costs, what you get, and
  # what happens after you pay. Anything more is a tier table pretending a
  # choice exists.
  #
  # `::Pricing` is the top-level business-facts module, not this namespace.
  def page_title
    "Pricing"
  end

  def content
    render_intro
    render_offer
    render_how_it_works
  end

  private def render_intro
    section class: "intro" do
      div class: "intro-copy" do
        h1 class: "intro-title" do
          text "One posting, "
          span class: "accent" do
            text ::Pricing.summary
          end
        end

        para class: "intro-lede" do
          text "No plans, no seats, no renewals to cancel. You pay once when " \
               "you publish a role and it stays on the board until it expires."
        end
      end
    end
  end

  private def render_offer
    section class: "section" do
      div class: "form-container" do
        div class: "pricing-info" do
          h2 do
            text "Job posting - #{::Pricing.summary}"
          end
          ul do
            li do
              text "#{::Pricing.duration_days} days on the board from the moment payment clears"
            end
            li do
              text "Listed on the home page and in every relevant search"
            end
            li do
              text "Included in the weekly newsletter"
            end
            li do
              text "Editable for the whole run of the posting"
            end
            li do
              text "Charged once. There is nothing to cancel and nothing recurring."
            end
          end
        end

        div class: "intro-cta" do
          a href: "/jobs/new", class: "button button-primary button-large" do
            text "Post a Job - #{::Pricing.price_label}"
          end
        end
      end
    end
  end

  private def render_how_it_works
    section class: "section" do
      div class: "section-header" do
        h2 do
          text "How it works"
        end
        para class: "section-subtitle" do
          text "A posting is written first and paid for second, so you can " \
               "see exactly what you are buying before you are charged."
        end
      end

      div class: "recipe-grid" do
        step(
          "Write the posting",
          "Fill in the role, the company and how to apply. Nothing is charged at this point and the posting is not yet visible.",
          "crystalgigs.com/jobs/new"
        )
        step(
          "Pay #{::Pricing.price_label}",
          "Card payment is handled by Stripe. Card details are entered on Stripe's own form and never reach this server.",
          "#{::Pricing.price_label} #{::Pricing::CURRENCY.upcase}, charged once"
        )
        step(
          "It goes live",
          "The posting publishes as soon as the payment clears and stays up for #{::Pricing.duration_days} days.",
          "crystalgigs.com/jobs"
        )
      end
    end
  end

  private def step(title : String, blurb : String, snippet : String)
    article class: "recipe" do
      h3 do
        text title
      end
      para do
        text blurb
      end
      div class: "code-block" do
        pre do
          code do
            text snippet
          end
        end
      end
    end
  end
end
