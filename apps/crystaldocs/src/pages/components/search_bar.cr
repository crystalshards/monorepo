class Components::SearchBar < Lucky::BaseComponent
  needs query : String?
  needs large : Bool = false

  def render
    form_for Docs::Index, class: form_class do
      input(
        type: "text",
        name: "query",
        value: query || "",
        placeholder: "Search documentation...",
        class: input_class
      )
      submit "Search", class: "search-button"
    end
  end

  private def form_class
    large? ? "search-form search-form-large" : "search-form"
  end

  private def input_class
    large? ? "search-input search-input-large" : "search-input"
  end
end
