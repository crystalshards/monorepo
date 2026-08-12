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
      h2 heading

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

  private def heading : String
    package.indexed? ? "No documentation yet" : "Not indexed yet"
  end

  # Three states, and only two of them are facts about the repository.
  #
  # The registry records a shard's identity when it discovers it and fetches
  # its tags on a later pass, so an empty release list means "we have not
  # looked" until it has been indexed. Reading that as "this repository
  # publishes no releases" told visitors that kemal, which has 65 tags, had
  # never cut one. We do not get to make a claim about somebody's repository
  # from a gap in our own database.
  private def explanation : String
    unless package.indexed?
      return "#{package.name} was found but its releases have not been read yet. " \
             "The registry records a repository when it finds it and fetches its " \
             "tags on a later pass, so this says nothing about whether " \
             "#{package.name} has releases. Check back shortly."
    end

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
