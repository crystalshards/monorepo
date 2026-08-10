abstract class MainLayout
  include Lucky::HTMLPage

  abstract def content
  abstract def page_title

  def render
    html_doctype

    html lang: "en" do
      mount Head, page_title: page_title

      body do
        mount Header
        main class: "container" do
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
