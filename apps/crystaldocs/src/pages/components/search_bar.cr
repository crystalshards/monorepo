class Components::SearchBar < Lucky::BaseComponent
  needs query : String?
  needs large : Bool = false
  # The masthead variant is icon-only and narrower, so it can live in the
  # navbar without crowding it.
  needs compact : Bool = false
  # Ids must be unique when the bar appears more than once on a page.
  needs field_id : String = "doc-search"

  def render
    form_for Docs::Index, class: form_classes do
      # A placeholder is not a label: it vanishes on input and is not a
      # dependable accessible name (WCAG 3.3.2).
      label "Search documentation", for: field_id, class: "visually-hidden"

      input(
        type: "search",
        id: field_id,
        name: "query",
        value: query || "",
        placeholder: "Search documentation...",
        class: input_classes,
        # Everything the typeahead needs, and nothing that changes the field
        # without it. `data-search-suggest` is both the switch and the
        # endpoint: no script, no attribute read, and this is an ordinary
        # search form that submits to /docs exactly as it always has.
        #
        # The minimum term travels from the server constant rather than being
        # written out again in JavaScript, so the client cannot start asking
        # at a length the endpoint refuses to answer.
        "data-search-suggest": Api::Docs::Suggestions.path,
        "data-search-suggest-min": CrystalDocs::PackageSuggestions::MINIMUM_TERM.to_s,
        "data-search-suggest-noun": "package",
        "data-search-suggest-listbox": listbox_id
      )

      button type: "submit", class: "search-button" do
        tag "i", class: "fa-solid fa-magnifying-glass", "aria-hidden": "true"
        if compact?
          span class: "visually-hidden" do
            text "Search"
          end
        else
          text " Search"
        end
      end

      # Empty and hidden until the script fills it. Rendered here rather than
      # built in JavaScript so its position in the form, and the CSS that
      # overlays it, are stated in one place; `hidden` keeps it out of the
      # accessibility tree and off the screen when there is no script.
      ul "",
        id: listbox_id,
        class: "search-suggestions",
        role: "listbox",
        "aria-label": "Package suggestions",
        hidden: "hidden"

      # Empty from the start, for the reason `Components::DocsSidebarNav` gives
      # for its filter status: a live region announces nothing when the region
      # itself and its first text arrive in the same update.
      para "",
        class: "visually-hidden",
        role: "status",
        "data-search-suggest-status": "true"
    end
  end

  private def listbox_id : String
    "#{field_id}-suggestions"
  end

  private def form_classes : String
    classes = ["search-form"]
    classes << "search-form-large" if large?
    classes << "search-form-compact" if compact?
    classes.join(" ")
  end

  private def input_classes : String
    classes = ["search-input"]
    classes << "search-input-large" if large?
    classes.join(" ")
  end
end
