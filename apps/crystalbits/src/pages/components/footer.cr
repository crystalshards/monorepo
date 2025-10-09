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
              li { a href: "/", do: text("Home") }
              li { a href: "/posts", do: text("All Posts") }
              li { a href: "https://crystalshards.org", target: "_blank", do: text("CrystalShards") }
              li { a href: "https://crystaldocs.org", target: "_blank", do: text("CrystalDocs") }
            end
          end

          div class: "footer-section" do
            h3 "Newsletter"
            para "Stay updated with the latest Crystal news and tutorials."
            mount NewsletterSignupForm, inline: true
          end
        end

        div class: "footer-bottom" do
          para "© 2025 CrystalBits. Part of the Crystal ecosystem."
        end
      end
    end
  end
end
