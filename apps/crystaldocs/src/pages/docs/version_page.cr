class Docs::VersionPage < MainLayout
  needs doc : Doc
  needs doc_version : DocVersion
  needs doc_content : String
  needs file_path : String

  def page_title
    "#{doc.package_name} v#{doc_version.version}"
  end

  def content
    div class: "docs-viewer" do
      render_docs_header
      render_docs_content
    end
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
        tag "option", value: "/docs/#{doc.package_name}/#{v.version}", selected: v.version == doc_version.version do
          text v.version
        end
      end
    end
  end

  private def render_docs_content
    div class: "docs-content-wrapper" do
      div class: "docs-content" do
        raw doc_content
      end
    end
  end
end
