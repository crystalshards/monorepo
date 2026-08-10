class Header < Lucky::BaseComponent
  # Search sits in the masthead, not in a landing hero. Finding a role is the
  # primary job of a job board, so it is reachable from every page and near
  # the top of the tab order rather than 574px down a marketing block. Hex and
  # RubyGems both do this; our previous landing pushed it below the fold.
  needs query : String? = nil

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

        mount SearchBar, query: @query, field_id: "masthead-search", compact: true

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
