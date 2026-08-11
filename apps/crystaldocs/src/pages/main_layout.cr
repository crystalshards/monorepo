abstract class MainLayout
  include Lucky::HTMLPage

  abstract def content
  abstract def page_title

  def render
    html_doctype

    html lang: "en" do
      mount Components::Head, page_title: page_title

      body do
        # First focusable element on the page, so keyboard users can bypass
        # the masthead instead of tabbing it on every navigation (WCAG 2.4.1).
        a "Skip to main content", href: "#main", class: "skip-link"

        mount Components::Header
        tag "main", class: "container", id: "main" do
          content
        end
        # After the content, before the footer. An ad never precedes what the
        # reader came for, and it renders nothing at all when CrystalGigs has
        # nothing to say, so this line adds no markup on a bad day.
        mount Components::JobAd
        mount Components::Footer
      end
    end
  end
end
