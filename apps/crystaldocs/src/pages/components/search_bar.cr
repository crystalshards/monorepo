class Components::SearchBar < Lucky::BaseComponent
  needs query : String?
  needs large : Bool = false
  # Ids must be unique when the bar appears more than once on a page.
  needs field_id : String = "doc-search"

  def render
    form_for Docs::Index, class: form_class do
      # A placeholder is not a label: it vanishes on input and is not a
      # dependable accessible name (WCAG 3.3.2).
      label "Search documentation", for: field_id, class: "visually-hidden"

      input(
        type: "search",
        id: field_id,
        name: "query",
        value: query || "",
        placeholder: "Search documentation...",
        class: input_class
      )

      button type: "submit", class: "search-button" do
        tag "i", class: "fa-solid fa-magnifying-glass", "aria-hidden": "true"
        text " Search"
      end
    end
  end

  private def form_class
    large? ? "search-form search-form-large" : "search-form"
  end

  private def input_class
    large? ? "search-input search-input-large" : "search-input"
  end
end
