class Pagination < Lucky::BaseComponent
  needs current_page : Int32
  needs total_pages : Int32

  def render
    return if @total_pages <= 1

    nav class: "pagination" do
      if @current_page > 1
        a href: build_page_url(@current_page - 1), class: "pagination-link" do
          text "← Previous"
        end
      end

      div class: "pagination-info" do
        text "Page #{@current_page} of #{@total_pages}"
      end

      if @current_page < @total_pages
        a href: build_page_url(@current_page + 1), class: "pagination-link" do
          text "Next →"
        end
      end
    end
  end

  private def build_page_url(page : Int32) : String
    params = URI::Params.build do |form|
      form.add("page", page.to_s)
    end
    "?#{params}"
  end
end
