class Docs::TypePage < MainLayout
  needs doc : Doc
  needs doc_version : DocVersion
  needs document : CrystalDocs::DocsDocument
  needs type : CrystalDocs::DocType
  needs linker : CrystalDocs::TypeLinker

  def page_title
    "#{type.full_name} - #{doc.package_name} #{doc_version.version}"
  end

  def content
    div class: "docs-shell" do
      mount Components::DocsSidebarNav,
        doc: doc,
        doc_version: doc_version,
        types: document.all_types,
        current_full_name: type.full_name

      div class: "docs-main" do
        render_header
        render_documentation
        render_constants
        render_methods("Constructors", type.constructors)
        render_methods("Class methods", type.class_methods)
        render_methods("Instance methods", type.instance_methods)
        render_methods("Macros", type.macros)
        render_nested_types
      end
    end
  end

  private def render_header
    header class: "docs-type-header" do
      span class: "docs-kind" do
        text type.display_kind
      end

      h1 class: "docs-type-name" do
        text type.full_name
      end

      render_ancestry
    end
  end

  # The inheritance chain is the fastest way to understand what a type is, and
  # every link in it is a name the reader may want to follow.
  private def render_ancestry
    ancestors = type.ancestors
    return if ancestors.nil? || ancestors.empty?

    para class: "docs-ancestry" do
      text "Inherits "

      ancestors.each_with_index do |ancestor, index|
        text " / " if index > 0
        render_type_link(ancestor.full_name)
      end
    end
  end

  # A cross link resolves in three steps: this package, then another package
  # we index, then the standard library. An unresolved name stays plain text
  # rather than becoming a link that guesses.
  # Most of the type references a reader wants to follow are in signatures,
  # not in the inheritance list, so the signature text is scanned for names
  # and every one that resolves becomes a link. Names that do not resolve are
  # left exactly as the compiler wrote them.
  private def render_linked_types(source : String)
    cursor = 0

    source.scan(/[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*/) do |match|
      text source[cursor...match.begin]
      cursor = match.end
      render_type_link(match[0])
    end

    text source[cursor..]
  end

  private def render_type_link(full_name : String)
    link = linker.link_for(full_name)

    unless link
      span class: "docs-ancestry-link" do
        text full_name
      end
      return
    end

    css = link.external ? "docs-ancestry-link docs-external" : "docs-ancestry-link"

    # A title is only present on cross links, where it names the package the
    # reader is about to leave for.
    if title = link.title
      a(href: link.href, class: css, title: title) { text full_name }
    else
      a(href: link.href, class: css) { text full_name }
    end
  end

  # `summary` arrives already rendered to HTML by the compiler, while `doc` is
  # the raw doc comment in Markdown. They need different treatment, and both
  # are shard-authored, so both are sanitised.
  private def render_documentation
    if summary = type.summary.presence
      div class: "docs-summary" do
        raw CrystalDocs::DocHtml.sanitize(summary)
      end
    end

    if body = type.doc.presence
      div class: "docs-doc" do
        raw CrystalDocs::DocHtml.markdown(body)
      end
    end
  end

  private def render_constants
    constants = type.constants
    return if constants.nil? || constants.empty?

    section class: "docs-section" do
      h2 class: "docs-section-heading" do
        text "Constants"
      end

      constants.each do |constant|
        div class: "docs-member" do
          div class: "docs-member-signature" do
            text constant.name
            if value = constant.value.presence
              text " = #{value}"
            end
          end

          if doc_text = constant.doc.presence
            div class: "docs-member-doc" do
              raw CrystalDocs::DocHtml.markdown(doc_text)
            end
          end
        end
      end
    end
  end

  private def render_methods(heading : String, methods : Array(CrystalDocs::DocMethod)?)
    return if methods.nil? || methods.empty?

    section class: "docs-section" do
      h2 class: "docs-section-heading" do
        text heading
      end

      methods.each do |method|
        div class: "docs-member", id: method.anchor do
          div class: "docs-member-signature" do
            span class: "docs-member-name" do
              text method.name
            end
            render_linked_types(method.args_string.to_s)

            if returns = method.return_type.presence
              text " : "
              render_linked_types(returns)
            end
          end

          # Prefer the full doc comment, which is Markdown, and fall back to
          # the compiler's rendered summary, which is already HTML.
          if body = method.doc.presence
            div class: "docs-member-doc" do
              raw CrystalDocs::DocHtml.markdown(body)
            end
          elsif summary = method.summary.presence
            div class: "docs-member-doc" do
              raw CrystalDocs::DocHtml.sanitize(summary)
            end
          end

          if url = method.location.try(&.url)
            a href: url, class: "docs-member-source", target: "_blank", rel: "noopener" do
              text "Source"
            end
          end
        end
      end
    end
  end

  private def render_nested_types
    nested = type.types
    return if nested.nil? || nested.empty?

    section class: "docs-section" do
      h2 class: "docs-section-heading" do
        text "Nested types"
      end

      ul class: "docs-toc" do
        nested.sort_by(&.full_name).each do |child|
          li do
            a(
              href: "/docs/#{doc.package_name}/#{doc_version.version}/#{child.url_path}",
              class: "docs-toc-link"
            ) do
              text child.full_name
            end
          end
        end
      end
    end
  end
end
