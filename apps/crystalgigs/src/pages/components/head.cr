class Head < Lucky::BaseComponent
  needs page_title : String

  # IBM Plex, three cuts with distinct jobs: Condensed for the vertical, cut
  # feel of headings, Sans for reading, Mono for counts and metadata because
  # those are data rather than prose.
  FONT_HREF = "https://fonts.googleapis.com/css2" \
              "?family=IBM+Plex+Sans+Condensed:wght@600;700" \
              "&family=IBM+Plex+Sans:wght@400;500;600" \
              "&family=IBM+Plex+Mono:wght@400;500" \
              "&display=swap"

  ICON_HREF = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css"

  # Deliberately no `meta name="robots"` tag anywhere in this component.
  # Every job posting depends on being crawled and indexed for Google Jobs
  # and every equivalent search feature to ever see it - a `noindex` here
  # would silently disqualify the entire board, on every page, with no error
  # anywhere to notice it by. Absence is the correct, indexable default,
  # which is also why this is a comment and not a redundant "index, follow"
  # tag: an explicit tag would not stop a future `noindex` from also being
  # added, it would just be one more thing to add alongside it. Add a
  # `noindex` on any *specific* page only for a documented reason, never
  # here where it would apply to all of them.
  def render
    head do
      meta charset: "utf-8"
      meta name: "viewport", content: "width=device-width, initial-scale=1"
      title "#{@page_title} - CrystalGigs"
      meta name: "description", content: "Find Crystal programming jobs and hire Crystal developers"

      # Light is the default; the stylesheet inverts under prefers-color-scheme.
      meta name: "color-scheme", content: "light dark"

      tag "link", rel: "preconnect", href: "https://fonts.googleapis.com"
      tag "link", rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: "anonymous"
      tag "link", rel: "stylesheet", href: FONT_HREF
      tag "link", rel: "stylesheet", href: ICON_HREF
      tag "link", rel: "stylesheet", href: asset("css/app.css")

      # Icons. The mark is the header's `.logo::before`, the same faceted
      # crystal section in this app's accent, so the four sites read as a
      # family in a tab strip and stay told apart by hue.
      #
      # Fixed root paths rather than `asset()`: a user agent asks for
      # `/favicon.ico` and follows `/manifest.json` on its own, so these URLs
      # are a contract with the browser and must never be rewritten.
      tag "link", rel: "icon", href: "/favicon.ico", sizes: "16x16 32x32 48x48"
      tag "link", rel: "icon", href: "/icon.svg", type: "image/svg+xml"
      tag "link", rel: "apple-touch-icon", href: "/apple-touch-icon.png"
      tag "link", rel: "manifest", href: "/manifest.json"

      # Browser chrome follows the page ground, so the two agree at the seam.
      meta name: "theme-color", content: "#f4f6f6", media: "(prefers-color-scheme: light)"
      meta name: "theme-color", content: "#070a0b", media: "(prefers-color-scheme: dark)"

      csrf_meta_tags
    end
  end
end
