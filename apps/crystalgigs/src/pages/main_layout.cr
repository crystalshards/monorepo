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
end
