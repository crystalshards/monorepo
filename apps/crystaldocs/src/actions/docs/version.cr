# The package overview at the bare-name URL, which is the one already live and
# indexed.
#
# It keeps serving exactly what it serves today for every package this app has
# a row under, which is what "already indexed" obliges: the standard library
# lives here, and so does every artifact built before a shard was identified by
# its repository.
#
# What changes is what happens when there is no such row. That used to be a
# flat 404 for every shard the registry had indexed and nobody had documented.
# Now the name goes to the registry, and `Docs::BareNameResolution` decides
# what a name is worth: one repository redirects to its own URL, where the
# version is registered and the build is asked for; several redirect nowhere,
# because a name is not an identity.
class Docs::Version < BrowserAction
  include Docs::VersionRendering
  include Docs::BareNameResolution

  get "/docs/:package_name/:version" do
    doc = DocQuery.new
      .preload_doc_versions
      .package_name(package_name)
      .first?

    doc_version = doc.try(&.doc_versions.find { |candidate| candidate.version == version })
    held = !doc.nil? && !doc_version.nil?

    response = resolve_bare_name(package_name, held) do |slug|
      CrystalDocs::PackagePaths.version_path(slug, version)
    end

    if response
      response
    elsif doc && doc_version
      render_version(doc, doc_version)
    else
      raise Lucky::RouteNotFoundError.new(context)
    end
  end
end
