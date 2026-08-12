# Several repositories publish a shard under the name in the URL, so the URL
# does not identify one package and this page hands the choice back rather than
# picking for the reader.
class Docs::AmbiguousNamePage < MainLayout
  needs name : String
  needs slugs : Array(String)

  def page_title
    name
  end

  def content
    div class: "doc-header" do
      div class: "doc-title-block" do
        h1 name, class: "doc-title"

        para class: "doc-description-large" do
          text "#{slugs.size} repositories publish a shard called "
          strong name
          text ". A name does not say which one you mean, so pick the repository you are looking for."
        end
      end
    end

    div class: "doc-section" do
      h2 "Repositories"

      ul class: "version-list" do
        slugs.each do |slug|
          li do
            a slug, href: CrystalDocs::PackagePaths.package_path(slug), class: "version-number"
          end
        end
      end
    end
  end
end
