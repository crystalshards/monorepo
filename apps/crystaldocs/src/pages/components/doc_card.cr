class Components::DocCard < Lucky::BaseComponent
  # A catalogue entry rather than a Doc row. Browse lists the registry's
  # packages, most of which this app has no row for at all, so the card has to
  # be able to render one. The homepage sections pass their own rows through
  # `PackageCatalogue.for_docs` to get the same shape.
  needs entry : CrystalDocs::PackageCatalogue::Entry
  # Cards appear under an h1 on the browse page and under an h2 in homepage
  # sections, so the level is set by the caller rather than baked into the
  # visual style.
  needs heading_level : Int32 = 2

  def render
    article class: "doc-card" do
      div class: "doc-card-header" do
        tag "h#{heading_level}", class: "doc-name" do
          a entry.heading, href: entry.path
        end

        if version = entry.version
          span version, class: "doc-version"
        end
      end

      # Which repository this is. Two of them can publish a shard under the
      # same name, so the name on its own does not identify a package, and the
      # catalogue is ordered by that name.
      if entry.qualified?
        para entry.key, class: "doc-slug"
      end

      if description = entry.description
        para description, class: "doc-description"
      end

      render_meta
    end
  end

  # A package nobody has built yet has no update time and no views, and
  # printing "0 views" under a blank timestamp reads as a dead package rather
  # than an unbuilt one. It says what is actually true instead: nothing is
  # built, and following the link is what builds it.
  private def render_meta
    div class: "doc-meta" do
      if entry.documented?
        render_built_meta
      else
        span class: "doc-unbuilt" do
          tag "i", class: "fa-regular fa-file-lines icon", "aria-hidden": "true"
          text " Not built yet"
        end
      end
    end
  end

  private def render_built_meta
    if updated = entry.last_updated_at
      span do
        # The glyph is decorative; the text carries the meaning.
        tag "i", class: "fa-regular fa-clock icon", "aria-hidden": "true"
        text " Updated #{time_ago(updated)}"
      end
    end

    span do
      tag "i", class: "fa-solid fa-eye icon", "aria-hidden": "true"
      text " #{entry.total_views} views"
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
