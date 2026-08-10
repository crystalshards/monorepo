class SearchBar < Lucky::BaseComponent
  needs query : String = ""
  needs placeholder : String = "Search posts"
  # The masthead variant is icon-only and narrower so it fits the navbar.
  needs compact : Bool = false
  # Ids must be unique if the bar ever appears twice on one page.
  needs field_id : String = "post-search"

  def render
    form action: "/posts", method: "get", class: form_classes do
      # A placeholder is not a label: it vanishes on input and is not a
      # dependable accessible name (WCAG 3.3.2).
      label "Search posts", for: @field_id, class: "visually-hidden"

      input(
        type: "search",
        id: @field_id,
        name: "search",
        value: @query,
        placeholder: @placeholder,
        class: "search-input"
      )

      button type: "submit", class: "search-button" do
        tag "i", class: "fa-solid fa-magnifying-glass", "aria-hidden": "true"
        if @compact
          span class: "visually-hidden" do
            text "Search"
          end
        else
          text " Search"
        end
      end
    end
  end

  private def form_classes : String
    classes = ["search-form"]
    classes << "search-form-compact" if @compact
    classes.join(" ")
  end
end
