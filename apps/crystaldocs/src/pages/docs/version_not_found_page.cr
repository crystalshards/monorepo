class Docs::VersionNotFoundPage < MainLayout
  needs doc : Doc
  needs doc_version : DocVersion
  needs file_path : String

  def page_title
    "Documentation Not Found"
  end

  def content
    div class: "error-page" do
      h1 "Documentation Not Found"

      para class: "error-message" do
        text "The documentation for "
        strong "#{doc.package_name} v#{doc_version.version}"
        text " could not be found."
      end

      if file_path != "index.html"
        para class: "error-hint" do
          text "The file "
          code file_path
          text " does not exist in this documentation version."
        end
      end

      div class: "error-actions" do
        a "View Other Versions", href: CrystalDocs::PackagePaths.package_path(doc.package_name), class: "button"
        a "Browse All Packages", href: "/docs", class: "button button-primary"
      end

      if doc_version.build_status == "failed"
        div class: "error-details" do
          h2 "Build Status"
          para "The documentation build for this version failed. Please contact the package maintainer."
        end
      elsif doc_version.build_status == "pending"
        div class: "error-details" do
          h2 "Build Status"
          para "The documentation for this version is currently being built. Please check back later."
        end
      end
    end
  end
end
