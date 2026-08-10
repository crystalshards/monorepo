class SearchBar < Lucky::BaseComponent
  needs query : String?
  needs large : Bool = false
  # The masthead variant is icon-only and narrower, so it can live in the
  # navbar without crowding it.
  needs compact : Bool = false
  needs action : String = "/jobs"
  # Ids must be unique when the bar appears more than once on a page.
  needs field_id : String = "job-search"

  def render
    form action: @action, method: "get", class: search_form_class do
      # A placeholder is not a label: it vanishes on input and is not a
      # dependable accessible name (WCAG 3.3.2).
      label "Search jobs", for: @field_id, class: "visually-hidden"

      input(
        type: "search",
        id: @field_id,
        name: "query",
        value: @query || "",
        placeholder: "Search for jobs, companies, or skills...",
        class: search_input_classes
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

  private def search_form_class
    classes = ["search-form"]
    classes << "search-form-large" if @large
    classes << "search-form-compact" if @compact
    classes.join(" ")
  end

  private def search_input_classes : String
    classes = ["search-input"]
    classes << "search-input-large" if @large
    classes.join(" ")
  end
end
