class Components::DocSidebar < Lucky::BaseComponent
  needs doc : Doc
  needs doc_version : DocVersion
  needs current_file : String

  def render
    aside class: "doc-sidebar" do
      render_package_info
      render_version_info
      render_quick_links
    end
  end

  private def render_package_info
    div class: "sidebar-section" do
      h2 doc.package_name, class: "sidebar-title"

      if description = doc.description
        para description, class: "sidebar-description"
      end
    end
  end

  private def render_version_info
    div class: "sidebar-section" do
      h3 "Version", class: "sidebar-heading"

      div class: "sidebar-version" do
        span doc_version.version, class: "version-tag"
        text " "
        a "Switch", href: "/docs/#{doc.package_name}", class: "version-switch-link"
      end

      if published = doc_version.published_at
        para class: "sidebar-meta" do
          text "Published #{format_date(published)}"
        end
      end

      div class: "build-status-badge status-#{doc_version.build_status}" do
        text "Build: #{doc_version.build_status.capitalize}"
      end
    end
  end

  private def render_quick_links
    div class: "sidebar-section" do
      h3 "Quick Links", class: "sidebar-heading"

      ul class: "sidebar-links" do
        li do
          a "Overview", href: "/docs/#{doc.package_name}/#{doc_version.version}", class: link_class("index.html")
        end

        if repository_url = doc.repository_url
          li do
            a "Repository", href: repository_url, target: "_blank", rel: "noopener"
          end
        end

        li do
          a "All Versions", href: "/docs/#{doc.package_name}"
        end

        li do
          a "CrystalShards", href: "https://crystalshards.org/shards/#{doc.package_name}", target: "_blank", rel: "noopener"
        end
      end
    end
  end

  private def link_class(file_path : String) : String
    current_file == file_path ? "sidebar-link active" : "sidebar-link"
  end

  private def format_date(time : Time) : String
    time.to_s("%b %-d, %Y")
  end
end
