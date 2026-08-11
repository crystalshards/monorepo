class Components::DocsSidebarNav < Lucky::BaseComponent
  needs doc : Doc
  needs doc_version : DocVersion
  needs types : Array(CrystalDocs::DocType)
  needs current_full_name : String?

  def render
    aside class: "docs-sidebar" do
      nav class: "docs-nav", "aria-label": "Package contents" do
        div class: "docs-nav-group" do
          h2 class: "docs-nav-heading" do
            a href: "/docs/#{doc.package_name}/#{doc_version.version}" do
              text doc.package_name
            end
          end

          para class: "docs-nav-version" do
            text doc_version.version
          end
        end

        # A registry package can define hundreds of types, so the list needs a
        # way to narrow it. This filters the rendered list without a request;
        # with scripting off the full list is still there and still complete.
        div class: "docs-nav-group" do
          label "Filter types", for: "docs-type-filter", class: "visually-hidden"
          input(
            type: "search",
            id: "docs-type-filter",
            class: "docs-nav-filter",
            placeholder: "Filter types",
            autocomplete: "off",
            "data-docs-filter": "true"
          )
        end

        render_type_list
      end
    end
  end

  private def render_type_list
    div class: "docs-nav-group" do
      h3 class: "docs-nav-heading" do
        text "Types"
      end

      if types.empty?
        para class: "docs-nav-empty" do
          text "This package defines no public types."
        end
      else
        ul class: "docs-nav-list" do
          types.each do |type|
            li class: "docs-nav-item", "data-name": type.full_name.downcase do
              a(
                href: "/docs/#{doc.package_name}/#{doc_version.version}/#{type.url_path}",
                class: link_class(type)
              ) do
                text type.full_name
              end
            end
          end
        end
      end
    end
  end

  private def link_class(type : CrystalDocs::DocType) : String
    if type.full_name == current_full_name
      "docs-nav-link is-current"
    else
      "docs-nav-link"
    end
  end
end
