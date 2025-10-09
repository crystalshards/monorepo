class Head < Lucky::BaseComponent
  needs page_title : String

  def render
    head do
      meta charset: "utf-8"
      meta name: "viewport", content: "width=device-width, initial-scale=1"
      title "#{@page_title} - CrystalShards"

      tag "link", rel: "stylesheet", href: asset("css/app.css")

      csrf_meta_tags
    end
  end
end
