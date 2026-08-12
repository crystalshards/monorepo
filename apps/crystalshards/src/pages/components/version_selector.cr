# The control that answers "which version am I looking at, and what else is
# there".
#
# A disclosure holding links rather than a `select`, deliberately. A `select`
# cannot navigate without JavaScript, so it needs a submit button beside it and
# it puts the version in a query string; links give every release its own
# addressable URL, work with JavaScript off, are keyboard operable with no code
# from us, and let a reader open an old version in a new tab. `details` is a
# real dropdown, it just happens to be one the platform already built.
class VersionSelector < Lucky::BaseComponent
  needs shard : Shard
  # Newest first. The caller has already sorted, because the sort is also the
  # sidebar's order and the two must not disagree.
  needs versions : Array(ShardVersion)
  needs selected : ShardVersion?
  # Whether the registry has actually read this repository's tags. Without it
  # an empty list reads as "this repository has no releases", which is a claim
  # about somebody else's repository made from a gap in ours.
  needs indexed : Bool

  def render
    if @versions.empty?
      # Not an empty control. A shard with no tags is the normal case in this
      # registry and the reader is told, in place, why there is nothing to pick.
      span class: "version-pill version-pill-empty" do
        text @indexed ? "No tagged releases" : "Not indexed yet"
      end
      return
    end

    tag "details", class: "version-picker" do
      tag "summary", class: "version-picker-summary" do
        span class: "visually-hidden" do
          text "Version, currently "
        end

        span class: "version-picker-current" do
          text @selected.try(&.label) || "unknown"
        end

        span class: "version-picker-count" do
          text release_count_label
        end

        tag "i", class: "fa-solid fa-angle-down version-picker-caret", "aria-hidden": "true"
      end

      ul class: "version-picker-list" do
        @versions.each { |version| render_option(version) }
      end
    end
  end

  private def render_option(version : ShardVersion)
    # aria-current marks the row the page is actually showing, which is the
    # only thing distinguishing it for a screen reader once it stops being a
    # link. Set by branching rather than by passing nil, because an empty
    # aria-current attribute is a different thing from an absent one.
    if current?(version)
      li class: "version-picker-item", "aria-current": "true" do
        render_option_target(version, current: true)
      end
    else
      li class: "version-picker-item" do
        render_option_target(version, current: false)
      end
    end
  end

  private def render_option_target(version : ShardVersion, current : Bool)
    if !current && (path = option_path(version))
      a href: path, class: "version-picker-option" do
        render_option_body(version)
      end
    else
      # The version already on screen is not a link to itself. Neither is a
      # version of a shard we could never identify: there is no host, owner
      # and repo to build a URL from, so the row is text and says so by
      # simply not being clickable.
      span class: "version-picker-option version-picker-option-static" do
        render_option_body(version)
      end
    end
  end

  private def render_option_body(version : ShardVersion)
    span class: "version-picker-label" do
      text version.label
    end

    if latest?(version)
      span class: "badge badge-latest" do
        text "latest"
      end
    end

    if version.yanked
      span class: "badge badge-yanked" do
        text "yanked"
      end
    end

    unless version.indexed?
      span class: "badge badge-unindexed" do
        text "not indexed"
      end
    end

    span class: "version-date" do
      text version.released_at.to_utc.to_s("%b %-d, %Y")
    end
  end

  # The newest release keeps the shard's canonical URL rather than a versioned
  # one, so navigating to latest lands on the address everything links to
  # instead of a second URL for the same page.
  private def option_path(version : ShardVersion) : String?
    return @shard.url_path if latest?(version)

    @shard.version_path(version.version)
  end

  private def latest?(version : ShardVersion) : Bool
    version.version == @versions.first.version
  end

  private def current?(version : ShardVersion) : Bool
    version.version == @selected.try(&.version)
  end

  private def release_count_label : String
    count = @versions.size
    count == 1 ? "1 version" : "#{count} versions"
  end
end
