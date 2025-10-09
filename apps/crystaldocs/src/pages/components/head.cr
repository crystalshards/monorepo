class Components::Head < Lucky::BaseComponent
  needs page_title : String

  def render
    head do
      utf8_charset
      title "#{page_title} - CrystalDocs.org"
      css_link asset("css/app.css")
      meta name: "viewport", content: "width=device-width, initial-scale=1"
      meta name: "description", content: "Crystal shard documentation hosting"
    end
  end
end
