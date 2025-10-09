class Errors::ShowPage < MainLayout
  needs message : String
  needs status : Int32

  def page_title
    "Error #{@status}"
  end

  def content
    section class: "section" do
      div class: "error-page" do
        h1 do
          text "Error #{@status}"
        end

        para class: "error-message" do
          text @message
        end

        a href: "/", class: "button" do
          text "Go to Homepage"
        end
      end
    end
  end
end
