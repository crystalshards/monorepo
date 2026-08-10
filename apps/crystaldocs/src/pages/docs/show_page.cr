class Docs::ShowPage < MainLayout
  needs doc : Doc

  def page_title
    doc.package_name
  end

  def content
    render_doc_header
    render_versions_list
  end

  private def render_doc_header
    div class: "doc-header" do
      div class: "doc-title-block" do
        h1 doc.package_name, class: "doc-title"

        if description = doc.description
          para description, class: "doc-description-large"
        end
      end

      div class: "doc-stats-block" do
        span class: "stat-item" do
          tag "i", class: "fa-solid fa-eye icon", "aria-hidden": "true"
          strong "#{doc.total_views}"
          text " views"
        end

        if updated = doc.last_updated_at
          span class: "stat-item" do
            tag "i", class: "fa-regular fa-clock icon", "aria-hidden": "true"
            text " Updated #{format_date(updated)}"
          end
        end
      end
    end
  end

  private def render_versions_list
    div class: "doc-section" do
      h2 "Available Versions"

      versions = doc.doc_versions.sort_by(&.published_at).reverse

      if versions.any?
        ul class: "version-list" do
          versions.each do |version|
            li do
              a version.version, href: "/docs/#{doc.package_name}/#{version.version}", class: "version-number"
              span format_date(version.published_at), class: "version-date"
            end
          end
        end
      else
        para "No documentation versions available yet", class: "empty-state"
      end
    end
  end

  private def format_date(time : Time) : String
    time.to_s("%Y-%m-%d")
  end
end
