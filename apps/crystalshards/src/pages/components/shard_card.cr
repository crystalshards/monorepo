class ShardCard < Lucky::BaseComponent
  needs shard : Shard
  # Cards appear under an h1 on listings and under an h2 in homepage sections,
  # so the level is set by the caller rather than baked into the visual style.
  needs heading_level : Int32 = 2
  # Passed in, never resolved here. A card that counted its own dependents
  # would be an N+1 that grows with the length of the listing, so the action
  # counts the whole page in one query and hands cards the answer.
  needs dependent_count : Int32

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
        # Stars are fetched from the host, so "not fetched yet" is a real
        # state and is rendered as one rather than hidden. Hiding it would
        # make an unindexed shard indistinguishable from a broken render, and
        # with the crawl only part way through the ecosystem that is the
        # common case here, not the edge case.
        span class: "shard-stars" do
          tag "i", class: "fa-solid fa-star icon", "aria-hidden": "true"

          if stars = @shard.github_stars
            text "#{stars} "
            span class: "visually-hidden" do
              text "stars"
            end
          else
            span class: "visually-hidden" do
              text "stars "
            end
            span class: "stat-unknown" do
              text "not indexed"
            end
          end
        end

        # Dependents are derived from our own dependency edges, so unlike
        # stars this can never be unknown: zero dependents is a measured fact.
        # There is no downloads figure because nothing is downloaded from this
        # registry, so that counter could only ever have read zero.
        span class: "shard-dependents" do
          tag "i", class: "fa-solid fa-diagram-project icon", "aria-hidden": "true"
          text "#{@dependent_count} "
          span class: "visually-hidden" do
            text "dependents"
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
