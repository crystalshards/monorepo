class Components::Breadcrumbs < Lucky::BaseComponent
  needs package_name : String
  needs version : String
  needs file_path : String

  def render
    nav class: "breadcrumbs" do
      a "CrystalDocs", href: "/"
      span " → "
      a "Browse", href: "/docs"
      span " → "
      a package_name, href: "/docs/#{package_name}"
      span " → "
      span version, class: "breadcrumb-version"

      unless file_path == "index.html"
        span " → "
        span display_file_name, class: "breadcrumb-current"
      end
    end
  end

  private def display_file_name : String
    # Remove .html extension and convert to readable format
    name = file_path.gsub(".html", "")
    parts = name.split("/")
    parts.last.gsub("-", " ").gsub("_", " ").titleize
  end
end
