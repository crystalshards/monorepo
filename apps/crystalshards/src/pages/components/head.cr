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
