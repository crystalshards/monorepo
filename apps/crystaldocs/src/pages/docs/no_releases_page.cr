# The registry has this repository, and there is no release to document.
#
# Every shard on crystalshards links here, including the many that have never
# cut a tag, because a link that only appears once documentation exists cannot
# be the thing that causes documentation to exist. So this page is the honest
# end of that link rather than a 404: the shard is real, we know exactly where
# it lives, and documentation is built per release because a release is the
# only thing there is to build.
class Docs::NoReleasesPage < MainLayout
  needs package : CrystalDocs::RegistryPackages::Package
  # Distinguishes a repository that has never tagged a release from one whose
  # releases have all been withdrawn. Both leave nothing to document, and they
  # are not the same news.
  needs withdrawn_count : Int32

  def page_title
    package.name
  end

  def content
    div class: "doc-header" do
      div class: "doc-title-block" do
        h1 package.name, class: "doc-title"

        # The identity, spelled out, because the name above is shared and the
        # slug is what makes this one repository.
        para class: "text-muted" do
          code package.slug
        end

        if description = package.description
          para description, class: "doc-description-large"
        end
      end
    end

    div class: "doc-section" do
      h2 "No documentation yet"

      para class: "empty-state" do
        text explanation
      end

      div class: "error-actions" do
        if repository_url = package.repository_url
          a "View the repository", href: repository_url, class: "button",
            target: "_blank", rel: "noopener"
        end

        a "Browse all packages", href: "/docs", class: "button button-primary"
      end
    end
  end

  private def explanation : String
    if withdrawn_count.zero?
      "#{package.name} has no published releases. Documentation is built from a " \
      "release, so there is nothing to build yet. Tag one and this page becomes " \
      "the documentation."
    else
      "Every published release of #{package.name} has been withdrawn, so there is " \
      "no current release to document. A withdrawn release still has its own " \
      "documentation URL if you have one."
    end
  end
end
