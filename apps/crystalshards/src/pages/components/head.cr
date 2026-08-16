class Head < Lucky::BaseComponent
  needs page_title : String

  # IBM Plex, three cuts with distinct jobs: Condensed for the vertical, cut
  # feel of headings, Sans for reading, Mono for versions and counts because
  # those are data rather than prose.
  FONT_HREF = "https://fonts.googleapis.com/css2" \
              "?family=IBM+Plex+Sans+Condensed:wght@600;700" \
              "&family=IBM+Plex+Sans:wght@400;500;600" \
              "&family=IBM+Plex+Mono:wght@400;500" \
              "&display=swap"

  ICON_HREF = "https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css"

  def render
    head do
      meta charset: "utf-8"
      meta name: "viewport", content: "width=device-width, initial-scale=1"
      title "#{@page_title} - CrystalShards"
      meta name: "description", content: "The package registry for the Crystal programming language."

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

      # Progressive enhancement, and only that. The masthead field is a plain
      # GET form that submits to /shards; this adds the suggestion list on top
      # of it and does nothing else.
      tag "script", src: asset("js/search_suggest.js"), defer: "defer"

      # The announcement bar is a complete, server-rendered element without
      # this; the script only reveals its dismiss control and remembers the
      # choice.
      tag "script", src: asset("js/announcement_bar.js"), defer: "defer"

      render_csrf_meta_tags
    end
  end

  # The CSRF token is seeded by a pipe that only runs when a route matched, so
  # on an unmatched path there is no session key and `csrf_meta_tags` raises.
  # That turned every 404 in this app into a 500: the error page extends the
  # same layout, so rendering the "not found" page was itself an exception.
  #
  # A page rendered without a session has no form to protect, so omitting the
  # tag is correct rather than a workaround.
  private def render_csrf_meta_tags
    return unless context.session.get?(Lucky::ProtectFromForgery::SESSION_KEY)

    csrf_meta_tags
  end
end
