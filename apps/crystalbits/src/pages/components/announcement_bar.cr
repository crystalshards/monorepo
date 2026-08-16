# The launch bar: one quiet line at the very top of every page, above the
# masthead, pointing at this site's announcement. CrystalBits' own
# announcement lives on CrystalBits itself, so the bar links to a post on
# this same origin.
#
# It renders in the layout, so the bar is on the page with or without
# JavaScript, and it stays. The only scripted part is the dismiss control,
# which arrives `hidden` and is revealed by public/js/announcement_bar.js; if
# that script never runs the bar is complete without it.
class AnnouncementBar < Lucky::BaseComponent
  # The one announcement this site points at, fixed by the launch plan: one
  # article per property, published on CrystalBits.
  SLUG = "a-place-to-write-about-crystal"

  def render
    # A named aside is a landmark, so a screen reader can list it and skip
    # past it rather than reading the line aloud on every page.
    aside class: "announcement-bar", "aria-label": "Announcement",
      "data-announcement-bar": "true", "data-announcement-slug": SLUG do
      div class: "announcement-bar-inner" do
        para do
          text "The posts here today are ours. The point of this site is everyone else: "
          a "A place to write about Crystal", href: announcement_url
          text "."
        end
        button type: "button", class: "announcement-bar-dismiss", hidden: "hidden",
          "data-announcement-dismiss": "true" do
          text "Dismiss"
        end
      end
    end
  end

  # The origin is a deployment fact read from configuration, never a literal,
  # for the same reason the footer's cross links go through SiteLinks.
  private def announcement_url : String
    "#{SiteLinks.origin(:crystalbits)}/posts/#{SLUG}"
  end
end
