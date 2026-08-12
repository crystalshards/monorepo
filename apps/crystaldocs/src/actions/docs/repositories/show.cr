# A repository without a version: send the reader to the release they meant.
#
# This is the URL every shard on crystalshards links to, so it has to be
# answerable for all of the registry's shards and not only for the handful
# anyone has documented before. The linking app deliberately does not name a
# version: "the current release" is a fact that moves, and a version baked into
# another site's page goes stale the next time a maintainer tags.
#
# Three answers, and they are not interchangeable:
#
#   the registry has it       -> its current release, or an honest page saying
#                                there is nothing to document yet.
#   the registry says no      -> 404. Not a shard.
#   the registry cannot say   -> whatever this app already holds, because
#                                documentation we have built is ours to serve
#                                and a second database being down is not a
#                                reason to lose it.
class Docs::Repositories::Show < BrowserAction
  get "/docs/_/:host/:owner/:repo" do
    slug = "#{host}/#{owner}/#{repo}"
    registry = CrystalDocs::RegistryPackages.build
    lookup = registry.find(slug)

    if package = lookup.package
      show_registered(registry, slug, package)
    elsif lookup.registry_answered?
      raise Lucky::RouteNotFoundError.new(context)
    else
      doc = DocQuery.new.preload_doc_versions.package_name(slug).first?
      raise Lucky::RouteNotFoundError.new(context) if doc.nil?

      redirect_to_current(doc)
    end
  end

  private def show_registered(
    registry : CrystalDocs::RegistryPackages,
    slug : String,
    package : CrystalDocs::RegistryPackages::Package,
  )
    releases = registry.releases(slug)

    if release = CrystalDocs::RegistryPackages.default_release(releases)
      redirect to: CrystalDocs::PackagePaths.version_path(slug, release.version)
    else
      # A real shard with nothing to default to. Not a 404: the difference
      # between "no such shard" and "a shard with no release" is the whole
      # question the reader arrived with, and the link that brought them here
      # exists precisely so that arriving is what starts a build.
      #
      # A version this app happens to hold is not consulted as a substitute.
      # The only way to get here with one is a release the registry has since
      # withdrawn, and redirecting to it would make a withdrawn release the
      # default, which is the one thing the default is never allowed to be.
      html Docs::NoReleasesPage,
        package: package,
        withdrawn_count: releases.count(&.yanked)
    end
  end

  private def redirect_to_current(doc : Doc)
    if current_version = doc.current_version
      redirect to: CrystalDocs::PackagePaths.version_path(doc.package_name, current_version)
    else
      html Docs::ShowPage, doc: doc
    end
  end
end
