class Head < Lucky::BaseComponent
  needs page_title : String

  def render
    head do
      meta charset: "utf-8"
      meta name: "viewport", content: "width=device-width, initial-scale=1"
      title "#{@page_title} - CrystalGigs"
      css_link asset("css/app.css")
      meta name: "description", content: "Find Crystal programming jobs and hire Crystal developers"
      csrf_meta_tags
    end
  end
end
