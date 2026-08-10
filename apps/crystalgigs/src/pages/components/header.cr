class Header < Lucky::BaseComponent
  def render
    header class: "site-header" do
      nav class: "navbar", "aria-label": "Primary" do
        div class: "navbar-brand" do
          # The mark is drawn in CSS as a bevelled square (the cube face of
          # pyrite), never an emoji.
          a href: "/", class: "logo" do
            text "CrystalGigs"
          end
        end

        div class: "navbar-menu" do
          a href: "/", class: "nav-link" do
            text "Home"
          end
          a href: "/jobs", class: "nav-link" do
            text "Browse Jobs"
          end
          a href: "/jobs/new", class: "nav-link nav-link-primary" do
            text "Post a Job"
          end
        end
      end
    end
  end
end
