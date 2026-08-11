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
              # rel=noopener goes with every target=_blank: without it the
              # opened page can reach back through window.opener.
              li { a href: "https://crystalshards.org", target: "_blank", rel: "noopener" do
                text "CrystalShards"
              end }
              li { a href: "https://crystaldocs.org", target: "_blank", rel: "noopener" do
                text "CrystalDocs"
              end }
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
        end
      end
    end
  end
end
