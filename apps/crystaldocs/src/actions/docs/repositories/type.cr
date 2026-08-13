# One type out of a repository's documentation.
#
# The route is split into a first segment and a glob rather than one glob,
# for the reason `Docs::Type` records: LuckyRouter also registers a glob's base
# path, so a plain trailing glob would claim the version route and collide with
# it, which crashes the app at boot.
#
# The two segments are rejoined, so a URL reads the way a Crystal name does:
#   /docs/_/github.com/kemalcr/kemal/1.6.0/Kemal/Config  ->  Kemal::Config
#
# This route never registers rows and never enqueues. A type path is attacker
# shaped, because any invented path parses, so an unbuilt version is handed to
# the version route, which is the one URL allowed to commission a build and is
# keyed on the version rather than on the path.
class Docs::Repositories::Type < BrowserAction
  include Docs::TypeRendering
  include Docs::CoreRepository

  get "/docs/_/:host/:owner/:repo/:version/:top_level/*:rest" do
    slug = "#{host}/#{owner}/#{repo}"

    if core_repository?(slug)
      # Carries the type through, so a link to a specific core type lands on
      # that type rather than the front of the library.
      redirect to: CrystalDocs::PackagePaths.type_path(CrystalDocs::CORE_PACKAGE, version, requested_path), status: 301
    else
      doc = DocQuery.new
        .preload_doc_versions
        .package_name(slug)
        .first?

      raise Lucky::RouteNotFoundError.new(context) if doc.nil?

      doc_version = doc.doc_versions.find { |candidate| candidate.version == version }

      if doc_version.nil?
        redirect_to_current_version(doc)
      else
        render_type(doc, doc_version, requested_path)
      end
    end
  end

  # The version segment does not name a version this app holds. Usually that
  # means a link written without one, so send the reader to the same type in
  # the current version rather than dead-ending one segment from correct.
  private def redirect_to_current_version(doc : Doc)
    current = doc.current_version

    if current && current != version
      redirect to: CrystalDocs::PackagePaths.type_path(
        doc.package_name,
        current,
        "#{version}/#{requested_path}"
      )
    else
      raise Lucky::RouteNotFoundError.new(context)
    end
  end

  # The router hands back the first segment and the remainder separately.
  private def requested_path : String
    tail = rest

    if tail && !tail.empty?
      "#{top_level}/#{tail}"
    else
      top_level
    end
  end
end
