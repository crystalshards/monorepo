class Docs::VersionPage < MainLayout
  needs doc : Doc
  needs doc_version : DocVersion
  needs document : CrystalDocs::DocsDocument?

  def page_title
    "#{doc.package_name} #{doc_version.version}"
  end

  def content
    div class: "docs-shell" do
      mount Components::DocsSidebarNav,
        doc: doc,
        doc_version: doc_version,
        types: document.try(&.all_types) || [] of CrystalDocs::DocType,
        current_full_name: nil

      div class: "docs-main" do
        render_header

        if parsed = document
          render_readme(parsed)
          render_type_index(parsed)
        else
          render_unavailable
        end
      end
    end
  end

  # Breadcrumbs, the version switcher and the build badge predate the JSON
  # renderer and are still the only way to move between versions or to see
  # that a build failed, so they survive the rewrite. The switcher's label
  # association in particular was an accessibility fix; do not drop it again.
  private def render_header
    mount Components::Breadcrumb, items: [
      Components::Breadcrumb::BreadcrumbItem.new("Home", "/"),
      Components::Breadcrumb::BreadcrumbItem.new("Documentation", "/docs"),
      Components::Breadcrumb::BreadcrumbItem.new(doc.package_name, "/docs/#{doc.package_name}"),
      Components::Breadcrumb::BreadcrumbItem.new(doc_version.version, "/docs/#{doc.package_name}/#{doc_version.version}"),
    ]

    header class: "docs-type-header" do
      span class: "docs-kind" do
        text "package"
      end

      h1 class: "docs-type-name" do
        text doc.package_name
      end

      para class: "docs-ancestry" do
        text doc_version.version

        if published = doc_version.published_at
          text " / published #{published.to_s("%b %-d, %Y")}"
        end

        if url = doc.repository_url
          text " / "
          a href: url, class: "docs-ancestry-link docs-external", target: "_blank", rel: "noopener" do
            text "repository"
          end
        end
      end

      render_version_switcher
      render_build_status

      if description = doc.description
        para class: "docs-summary" do
          text description
        end
      end
    end
  end

  # The label carries `for` and the select carries the matching `id`. A screen
  # reader announced this as a bare "combo box" before that was fixed.
  private def render_version_switcher
    versions = doc.doc_versions.sort_by(&.version).reverse
    return if versions.size < 1

    div class: "docs-version-switcher" do
      label "Version:", for: "version-select"

      tag "select", id: "version-select", onchange: "window.location.href = this.value" do
        versions.each do |candidate|
          href = "/docs/#{doc.package_name}/#{candidate.version}"

          if candidate.version == doc_version.version
            tag("option", value: href, selected: "selected") { text candidate.version }
          else
            tag("option", value: href) { text candidate.version }
          end
        end
      end
    end
  end

  # A failed or pending build is the explanation for a thin page, so it is
  # stated rather than left for the reader to infer.
  private def render_build_status
    para class: "docs-build-status" do
      text "Build: "
      strong doc_version.build_status.to_s
    end
  end

  # The README is raw Markdown in the document, and it was written by whoever
  # published the shard, so it is rendered and sanitised rather than trusted.
  private def render_readme(parsed : CrystalDocs::DocsDocument)
    body = parsed.body
    return unless body && !body.empty?

    section class: "docs-section" do
      div class: "docs-readme" do
        raw CrystalDocs::DocHtml.markdown(body)
      end
    end
  end

  private def render_type_index(parsed : CrystalDocs::DocsDocument)
    types = parsed.top_level_types

    section class: "docs-section" do
      h2 class: "docs-section-heading" do
        text "API"
      end

      if types.empty?
        para do
          text "This version publishes no documented types."
        end
      else
        ul class: "docs-toc" do
          types.each do |type|
            li do
              a(
                href: "/docs/#{doc.package_name}/#{doc_version.version}/#{type.url_path}",
                class: "docs-toc-link"
              ) do
                text type.full_name
              end

              if summary = type.summary.presence
                div class: "docs-member-doc" do
                  raw CrystalDocs::DocHtml.sanitize(summary)
                end
              end
            end
          end
        end
      end
    end
  end

  # No document. The version exists, so say what is actually wrong instead of
  # implying the package was never documented.
  private def render_unavailable
    section class: "docs-section" do
      h2 class: "docs-section-heading" do
        text "Documentation is not available for this version"
      end

      para do
        text "The documentation build for "
        strong "#{doc.package_name} #{doc_version.version}"
        text " has not produced a result yet, or could not be loaded from storage."
      end

      para do
        a "Browse the other versions", href: "/docs/#{doc.package_name}"
      end
    end
  end
end
