abstract class MainLayout
  include Lucky::HTMLPage

  abstract def content
  abstract def page_title

  def render
    html_doctype

    html lang: "en" do
      mount Components::Head, page_title: page_title

      body do
        mount Components::Header
        main class: "container" do
          content
        end
        mount Components::Footer
      end
    end
  end
end
