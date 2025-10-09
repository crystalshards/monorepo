class Components::DocCard < Lucky::BaseComponent
  needs doc : Doc

  def render
    div class: "doc-card" do
      div class: "doc-card-header" do
        h3 class: "doc-name" do
          a doc.package_name, href: "/docs/#{doc.package_name}"
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
          span "Updated #{time_ago(updated)}"
        end
        span "#{doc.total_views} views"
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
