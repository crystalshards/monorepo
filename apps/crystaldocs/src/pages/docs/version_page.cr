class Docs::VersionPage < MainLayout
  needs doc : Doc
  needs doc_version : DocVersion
  needs doc_content : String?
  needs file_path : String

  def page_title
    "#{doc.package_name} v#{doc_version.version}"
  end

  def content
    render_breadcrumbs

    div class: "docs-viewer" do
      render_docs_header

      div class: "docs-layout" do
        mount Components::DocSidebar,
          doc: doc,
          doc_version: doc_version,
          current_file: file_path

        render_docs_content
      end
    end
  end

  private def render_breadcrumbs
    breadcrumb_items = [
      Components::Breadcrumb::BreadcrumbItem.new("Home", "/"),
      Components::Breadcrumb::BreadcrumbItem.new("Documentation", "/docs"),
      Components::Breadcrumb::BreadcrumbItem.new(doc.package_name, "/docs/#{doc.package_name}"),
      Components::Breadcrumb::BreadcrumbItem.new("v#{doc_version.version}", "/docs/#{doc.package_name}/#{doc_version.version}"),
    ]

    mount Components::Breadcrumb, items: breadcrumb_items
  end

  private def render_docs_header
    div class: "docs-header" do
      div class: "docs-nav" do
        a "← Back to #{doc.package_name}", href: "/docs/#{doc.package_name}", class: "back-link"

        div class: "version-switcher" do
          render_version_dropdown
        end
      end

      div class: "docs-title-block" do
        h1 do
          text doc.package_name
          span " v#{doc_version.version}", class: "version-badge"
        end

        if description = doc.description
          para description, class: "docs-subtitle"
        end
      end

      if repository_url = doc.repository_url
        div class: "docs-links" do
          a "View Source", href: repository_url, class: "docs-link", target: "_blank"
          a "CrystalShards", href: "https://crystalshards.org/shards/#{doc.package_name}", class: "docs-link", target: "_blank"
        end
      end
    end
  end

  private def render_version_dropdown
    versions = doc.doc_versions.sort_by(&.published_at).reverse

    label "Version:"
    tag "select", id: "version-select", onchange: "window.location.href = this.value" do
      versions.each do |v|
        version_option(v.version, v.version == doc_version.version)
      end
    end
  end

  # `selected` is a boolean attribute: rendering selected="false" still marks
  # the option selected, which left every option selected and the browser
  # showing the last one rather than the version actually being viewed.
  private def version_option(version : String, selected : Bool)
    href = "/docs/#{doc.package_name}/#{version}"

    if selected
      tag "option", value: href, selected: "selected" do
        text version
      end
    else
      tag "option", value: href do
        text version
      end
    end
  end

  private def render_docs_content
    div class: "docs-content-wrapper" do
      if content = doc_content
        div class: "docs-content" do
          raw content
        end
      else
        render_content_unavailable
      end
    end
  end

  # Rendered when storage did not hand us the documentation body. The package
  # and version exist, so say what is actually wrong instead of implying the
  # documentation was never published.
  private def render_content_unavailable
    div class: "docs-content docs-content-unavailable" do
      h2 "Documentation content is temporarily unavailable"

      para do
        text "We could not load the documentation for "
        strong "#{doc.package_name} v#{doc_version.version}"
        text " from storage. This version is published, so the problem is on our end."
      end

      para class: "docs-content-hint" do
        text "Try again in a moment, or "
        a "browse the other versions", href: "/docs/#{doc.package_name}"
        text "."
      end
    end
  end
end
