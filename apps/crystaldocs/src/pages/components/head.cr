class Components::Head < Lucky::BaseComponent
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
      title "#{page_title} - CrystalDocs.org"
      meta name: "description", content: "Crystal shard documentation hosting"

      # Light is the default; the stylesheet inverts under prefers-color-scheme.
      meta name: "color-scheme", content: "light dark"

      tag "link", rel: "preconnect", href: "https://fonts.googleapis.com"
      tag "link", rel: "preconnect", href: "https://fonts.gstatic.com", crossorigin: "anonymous"
      tag "link", rel: "stylesheet", href: FONT_HREF
      tag "link", rel: "stylesheet", href: ICON_HREF
      tag "link", rel: "stylesheet", href: asset("css/app.css")

      # Syntax highlighting with Prism.js
      tag "link", rel: "stylesheet", href: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism.min.css"
      tag "link", rel: "stylesheet", href: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css"
      tag "script", src: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js", defer: "defer"
      tag "script", src: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-crystal.min.js", defer: "defer"

      # Progressive enhancement, and only that. The sidebar tree is
      # <details>/<summary> and its current branch is opened server side; this
      # adds the filter field's behaviour and nothing else, and no-ops on every
      # page that has no sidebar.
      tag "script", src: asset("js/docs_nav.js"), defer: "defer"

      csrf_meta_tags
    end
  end
end
