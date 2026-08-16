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
        # the masthead instead of tabbing it on every navigation (WCAG 2.4.1).
        a "Skip to main content", href: "#main", class: "skip-link"

        # Above the masthead, and after the skip link so the skip link stays
        # the first thing a keyboard user reaches. Static, not pinned: it
        # scrolls away with the first screenful, leaving the sticky masthead
        # to pin at the viewport top exactly as it always has.
        mount AnnouncementBar
        mount Header
        tag "main", class: "container", id: "main" do
          mount FlashMessages, @context.flash
          content
        end
        mount Footer
      end
    end
  end

  # `selected` and `checked` are HTML boolean attributes: the browser honours
  # them whenever they are present, so selected="false" still selects and
  # checked="false" still checks. They must be omitted entirely when off.
  private def select_option(label : String, value : String, selected : Bool)
    if selected
      option value: value, selected: "selected" do
        text label
      end
    else
      option value: value do
        text label
      end
    end
  end

  private def checkbox_input(name : String, id : String, value : String, checked : Bool)
    if checked
      input type: "checkbox", name: name, id: id, value: value, checked: "checked"
    else
      input type: "checkbox", name: name, id: id, value: value
    end
  end
end
