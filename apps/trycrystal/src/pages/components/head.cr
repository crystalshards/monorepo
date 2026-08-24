class Head < Lucky::BaseComponent
  needs page_title : String

  # IBM Plex, the family the other crystalshards.org sites are set in, so
  # trycrystal reads as one of them in a tab strip: Mono carries the console
  # because everything in it is code or output, Sans Condensed the wordmark,
  # Sans the small print.
  FONT_HREF = "https://fonts.googleapis.com/css2" \
              "?family=IBM+Plex+Mono:wght@400;500;600" \
              "&family=IBM+Plex+Sans:wght@400;500;600" \
              "&family=IBM+Plex+Sans+Condensed:wght@600;700" \
              "&display=swap"

  def render
    head do
      meta charset: "utf-8"
      meta name: "viewport", content: "width=device-width, initial-scale=1"
      title @page_title
      meta name: "description", content: "Learn Crystal in the browser. Read the " \
                                         "lesson, write real Crystal, run it in a sandbox. No signup."

      # Light is the default; the stylesheet inverts under prefers-color-scheme.
      # The console panel stays dark in both, because it is a terminal.
      meta name: "color-scheme", content: "light dark"

      tag "link", rel: "preconnect", href: "https://fonts.googleapis.com"
      tag "link", rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: "anonymous"
      tag "link", rel: "stylesheet", href: FONT_HREF
      tag "link", rel: "stylesheet", href: asset("css/app.css")

      # A fixed root path rather than asset(): the browser asks for
      # /icon.svg on its own, so that URL is a contract with it.
      tag "link", rel: "icon", href: "/icon.svg", type: "image/svg+xml"

      # Browser chrome follows the page ground, so the two agree at the seam.
      meta name: "theme-color", content: "#f4f6f6", media: "(prefers-color-scheme: light)"
      meta name: "theme-color", content: "#070a0b", media: "(prefers-color-scheme: dark)"

      tag "script", src: asset("js/console.js"), defer: "defer"
    end
  end
end
