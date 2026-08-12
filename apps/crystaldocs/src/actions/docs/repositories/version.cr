# The package overview, addressed by repository: README, top level API, and the
# sidebar that leads into individual types.
#
# This is the route that makes lazy building reachable. The enqueue half has
# always been here, but it could only ever fire for a package somebody had
# already inserted rows for, and rows only appeared after a build had already
# happened. Every shard the registry had indexed and nobody had documented was
# on the wrong side of that circle: the action looked for a Doc, found none,
# and raised route-not-found before the build could be asked for.
#
# So identity is settled against the registry first, and a repository it has
# published at this version gets its rows registered here before going down
# exactly the path a package with rows has always taken. Nothing about building
# changes, and in particular nothing is built inline: a build clones a
# repository and compiles third party code, which is the launcher's job.
#
# Asking the registry on every view, rather than only on the first, is what
# makes "the registry has never published this" a property of the URL instead
# of a property of whatever rows happen to exist. A URL that 404s today cannot
# start returning 200 because something once wrote a row under that key.
class Docs::Repositories::Version < BrowserAction
  include Docs::VersionRendering

  get "/docs/_/:host/:owner/:repo/:version" do
    slug = "#{host}/#{owner}/#{repo}"
    registry = CrystalDocs::RegistryPackages.build
    lookup = registry.find(slug)

    if package = lookup.package
      serve_published(registry, slug, package)
    elsif lookup.registry_answered?
      # The registry answered, and there is no such repository. Not a shard.
      raise Lucky::RouteNotFoundError.new(context)
    else
      serve_held(slug)
    end
  end

  private def serve_published(
    registry : CrystalDocs::RegistryPackages,
    slug : String,
    package : CrystalDocs::RegistryPackages::Package,
  )
    releases = registry.releases(slug)
    release = releases.find { |candidate| candidate.version == version }

    # The registry has the repository but not this version, so the URL names
    # nothing. Checked before anything this app holds is consulted: a row is
    # evidence that a version was built, never evidence that it exists, and
    # registering one anyway would commission a build for a release that is
    # not there, which is how a URL bar turns into a build queue.
    raise Lucky::RouteNotFoundError.new(context) if release.nil?

    if held = held_version(slug)
      return render_version(held[0], held[1])
    end

    default = CrystalDocs::RegistryPackages.default_release(releases)

    doc = CrystalDocs::PackageRegistration.doc_for(package, default.try(&.version))
    doc_version = CrystalDocs::PackageRegistration.version_for(doc, release)

    # Re-read so the version switcher shows every version this package has
    # collected, including the one just registered.
    reloaded = DocQuery.new.preload_doc_versions.package_name(slug).first? || doc

    render_version(reloaded, doc_version)
  end

  # The registry could not be reached, so whether this repository exists is
  # unknown. Documentation already built is entirely ours to serve, and losing
  # it because a second database is down is a worse failure than the one strict
  # checking would prevent. Nothing is registered on this path: registering
  # requires a published version, and there is nothing to read one from.
  private def serve_held(slug : String)
    held = held_version(slug)
    raise Lucky::RouteNotFoundError.new(context) if held.nil?

    render_version(held[0], held[1])
  end

  private def held_version(slug : String) : Tuple(Doc, DocVersion)?
    doc = DocQuery.new.preload_doc_versions.package_name(slug).first?
    return nil unless doc

    doc_version = doc.doc_versions.find { |candidate| candidate.version == version }
    return nil unless doc_version

    {doc, doc_version}
  end
end
