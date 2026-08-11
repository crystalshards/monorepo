class Components::DocsSidebarNav < Lucky::BaseComponent
  needs doc : Doc
  needs doc_version : DocVersion
  needs types : Array(CrystalDocs::DocType)
  needs current_full_name : String?

  # Returned instead of a fresh empty array for the common case, a type with no
  # nested types. The standard library is one of the packages rendered through
  # this component, so "once per leaf" is thousands of allocations.
  NO_TYPES = [] of CrystalDocs::DocType

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

        # A registry package can define hundreds of types, so the tree needs a
        # way to narrow it. This filters the rendered tree without a request;
        # with scripting off the tree is still there and still complete.
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

        render_type_tree
      end
    end
  end

  private def render_type_tree
    roots = root_types

    div class: "docs-nav-group" do
      h3 class: "docs-nav-heading" do
        text "Types"
      end

      if roots.empty?
        para class: "docs-nav-empty" do
          text "This package defines no public types."
        end
      else
        # Empty until the filter fills it. It is in the markup from the start
        # because a live region announces nothing when the region itself and
        # its first text arrive in the same update.
        para "", class: "docs-nav-status", role: "status", "data-docs-filter-status": "true"

        open_names = open_branch_names(roots)

        ul class: "docs-nav-list docs-nav-tree", "data-docs-nav-tree": "true" do
          roots.each { |type| render_node(type, open_names) }
        end
      end
    end
  end

  # One node per documented type, at whatever depth the package really nests
  # it. A namespace is a documented type too, so a node with children is a link
  # and a disclosure at once: `summary` owns the toggle, the `a` inside it owns
  # navigation. A click resolves to the nearest activatable element, so the
  # name navigates and the rest of the row folds, and the two never fight.
  # `details` also gives keyboard operation and the expanded/collapsed state
  # announcement for free, which a div with a click handler would not.
  private def render_node(type : CrystalDocs::DocType, open_names : Set(String))
    children = child_types(type)

    # The filter matches on the qualified name, so typing either the namespace
    # or the leaf finds the row, even though the row only shows the leaf.
    li class: "docs-nav-item", "data-name": type.qualified_name.downcase do
      if children.empty?
        render_type_link(type)
      else
        details(disclosure_attrs(type, open_names), class: "docs-nav-branch") do
          summary class: "docs-nav-summary" do
            render_type_link(type)
          end

          ul class: "docs-nav-list docs-nav-sublist" do
            children.each { |child| render_node(child, open_names) }
          end
        end
      end
    end
  end

  # `open` is decided here, on the server, from the current type's ancestry.
  # A reader with scripting blocked, a slow connection or a text browser still
  # arrives with the branch they are standing in already unfolded.
  private def disclosure_attrs(type : CrystalDocs::DocType, open_names : Set(String)) : Array(Symbol)
    open_names.includes?(type.full_name) ? [:open] : [] of Symbol
  end

  # The short name, not the qualified one. The tree already carries the
  # qualification, and `Kemal::Exceptions::CustomException` set solid across an
  # 18rem rail is the thing this replaces.
  private def render_type_link(type : CrystalDocs::DocType)
    href = "/docs/#{doc.package_name}/#{doc_version.version}/#{type.url_path}"

    if type.full_name == current_full_name
      a(href: href, class: "docs-nav-link is-current", "aria-current": "page") do
        text type.name
      end
    else
      a(href: href, class: "docs-nav-link") do
        text type.name
      end
    end
  end

  # Both docs pages hand this component the flattened `all_types`, and those
  # entries still carry `DocType#types`, so the roots are exactly the entries
  # that are not a child of another entry. Deriving them that way, rather than
  # splitting `full_name` on "::", keeps the tree honest: a level exists only
  # where the package really documents a type, and a type whose parent is not
  # documented stays a root instead of hanging off a node we invented. Handing
  # this component `top_level_types` instead produces the same roots, since no
  # root is a child of another root.
  private def root_types : Array(CrystalDocs::DocType)
    nested = Set(UInt64).new

    types.each do |type|
      type.types.try &.each { |child| nested << child.object_id }
    end

    types.reject { |type| nested.includes?(type.object_id) }.sort_by(&.name)
  end

  private def child_types(type : CrystalDocs::DocType) : Array(CrystalDocs::DocType)
    nested = type.types
    return NO_TYPES if nested.nil? || nested.empty?

    nested.sort_by(&.name)
  end

  # Every name on the path from a root down to the current type, including the
  # current type itself: standing on `Kemal::Config` should show what is nested
  # inside it, not just how you got there. A nil current type, which is the
  # overview page, gives an empty set and a fully collapsed tree.
  private def open_branch_names(roots : Array(CrystalDocs::DocType)) : Set(String)
    names = Set(String).new
    current = current_full_name
    return names unless current

    roots.each do |root|
      break if collect_open_path(root, current, names)
    end

    names
  end

  private def collect_open_path(type : CrystalDocs::DocType, current : String, names : Set(String)) : Bool
    if type.full_name == current
      names << type.full_name
      return true
    end

    found = child_types(type).any? { |child| collect_open_path(child, current, names) }
    names << type.full_name if found
    found
  end
end
