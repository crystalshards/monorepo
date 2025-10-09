class SearchBar < Lucky::BaseComponent
  needs query : String?
  needs large : Bool = false
  needs action : String = "/jobs"

  def render
    form action: @action, method: "get", class: search_form_class do
      div class: "search-input-group" do
        input(
          type: "text",
          name: "query",
          value: @query || "",
          placeholder: "Search for jobs, companies, or skills...",
          class: "search-input"
        )

        button type: "submit", class: "search-button" do
          text "Search"
        end
      end
    end
  end

  private def search_form_class
    classes = ["search-form"]
    classes << "search-form-large" if @large
    classes.join(" ")
  end
end
