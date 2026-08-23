abstract class MainLayout
  include Lucky::HTMLPage

  abstract def content
  abstract def page_title

  def render
    html_doctype

    html lang: "en" do
      mount Head, page_title: page_title

      body do
        # First focusable element on the page, so keyboard users can bypass
        # the masthead instead of tabbing it on every visit (WCAG 2.4.1).
        a "Skip to main content", href: "#main", class: "skip-link"

        tag "main", class: "shell", id: "main" do
          content
        end
      end
    end
  end
end
