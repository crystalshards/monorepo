class Components::DocCard < Lucky::BaseComponent
  needs doc : Doc
  # Cards appear under an h1 on the browse page and under an h2 in homepage
  # sections, so the level is set by the caller rather than baked into the
  # visual style.
  needs heading_level : Int32 = 2

  def render
    article class: "doc-card" do
      div class: "doc-card-header" do
        tag "h#{heading_level}", class: "doc-name" do
          a doc.package_name, href: CrystalDocs::PackagePaths.package_path(doc.package_name)
        end

        if version = doc.current_version
          span version, class: "doc-version"
        end
      end

      if description = doc.description
        para description, class: "doc-description"
      end

      div class: "doc-meta" do
        if updated = doc.last_updated_at
          span do
            # The glyph is decorative; the text carries the meaning.
            tag "i", class: "fa-regular fa-clock icon", "aria-hidden": "true"
            text " Updated #{time_ago(updated)}"
          end
        end
        span do
          tag "i", class: "fa-solid fa-eye icon", "aria-hidden": "true"
          text " #{doc.total_views} views"
        end
      end
    end
  end

  private def time_ago(time : Time) : String
    diff = Time.utc - time

    case
    when diff.total_minutes < 60
      "#{diff.total_minutes.to_i}m ago"
    when diff.total_hours < 24
      "#{diff.total_hours.to_i}h ago"
    when diff.total_days < 30
      "#{diff.total_days.to_i}d ago"
    else
      time.to_s("%Y-%m-%d")
    end
  end
end
