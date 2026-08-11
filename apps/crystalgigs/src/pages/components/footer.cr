class Footer < Lucky::BaseComponent
  def render
    footer class: "site-footer" do
      div class: "footer-content" do
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
            li do
              # rel=noopener goes with every target=_blank: without it the
              # opened page can reach back through window.opener.
              a href: "https://crystalshards.org", target: "_blank", rel: "noopener" do
                text "CrystalShards"
              end
            end
            li do
              a href: "https://crystaldocs.org", target: "_blank", rel: "noopener" do
                text "CrystalDocs"
              end
            end
            li do
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
      end
    end
  end
end
