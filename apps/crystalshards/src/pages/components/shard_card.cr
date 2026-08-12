class ShardCard < Lucky::BaseComponent
  needs shard : Shard
  # Cards appear under an h1 on listings and under an h2 in homepage sections,
  # so the level is set by the caller rather than baked into the visual style.
  needs heading_level : Int32 = 2

  def render
    article class: "shard-card" do
      div class: "shard-card-header" do
        tag "h#{@heading_level}", class: "shard-name" do
          a href: @shard.url_path do
            text @shard.name
          end
        end

        # Preload order is not guaranteed and released_at is not a real date on
        # any version except the indexed one, so this is chosen by semver. A
        # card and the page it links to must not name different latest versions.
        if version = VersionOrder.latest_version(@shard.shard_versions)
          span class: "version-number" do
            text version.version
          end
        end
      end

      # Two shards may share a name, so the card says which repository this one
      # is. Without it a listing of two "router" shards is unreadable.
      if slug = @shard.canonical_slug
        para class: "shard-identity" do
          text slug
        end
      end

      if description = @shard.description
        para class: "shard-description" do
          text description
        end
      end

      div class: "shard-meta" do
        if stars = @shard.github_stars
          span class: "shard-stars" do
            # The glyph is decorative; the count carries the meaning, and the
            # unit is spelled out for anyone not seeing the icon.
            tag "i", class: "fa-solid fa-star icon", "aria-hidden": "true"
            text "#{stars} "
            span class: "visually-hidden" do
              text "stars"
            end
          end
        end

        span class: "shard-downloads" do
          tag "i", class: "fa-solid fa-down-long icon", "aria-hidden": "true"
          text "#{@shard.total_downloads} "
          span class: "visually-hidden" do
            text "downloads"
          end
        end

        if license = @shard.license
          span class: "shard-license" do
            text license
          end
        end
      end
    end
  end
end
