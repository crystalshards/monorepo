class Components::Head < Lucky::BaseComponent
  needs page_title : String

  def render
    head do
      utf8_charset
      title "#{page_title} - CrystalDocs.org"
      css_link asset("css/app.css")
      meta name: "viewport", content: "width=device-width, initial-scale=1"
      meta name: "description", content: "Crystal shard documentation hosting"

      # Syntax highlighting with Prism.js
      tag "link", rel: "stylesheet", href: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism.min.css"
      tag "link", rel: "stylesheet", href: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css"
      tag "script", src: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js", defer: "defer"
      tag "script", src: "https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-crystal.min.js", defer: "defer"
    end
  end
end
