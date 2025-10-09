class SearchBar < Lucky::BaseComponent
  needs query : String = ""
  needs placeholder : String = "Search for shards..."
  needs large : Bool = false

  def render
    form action: "/shards", method: "get", class: search_form_classes do
      input(
        type: "search",
        name: "query",
        value: @query,
        placeholder: @placeholder,
        class: search_input_classes
      )
      button type: "submit", class: "search-button" do
        text "Search"
      end
    end
  end

  private def search_form_classes : String
    classes = ["search-form"]
    classes << "search-form-large" if @large
    classes.join(" ")
  end

  private def search_input_classes : String
    classes = ["search-input"]
    classes << "search-input-large" if @large
    classes.join(" ")
  end
end
