class Docs::Type < BrowserAction
  include Docs::TypeRendering
  include Docs::BareNameResolution

  # Renders one type from the package's docs.json.
  #
  # The route is split into a first segment and a glob rather than one glob,
  # because LuckyRouter also registers a glob's base path: a plain
  # /docs/:package_name/:version/*:type_path would claim
  # /docs/:package_name/:version and collide with Docs::Version, which crashes
  # the app at boot. Route helpers also cannot generate a path for a glob
  # route, so keeping the glob off Docs::Version leaves its .with helper
  # working everywhere it is used.
  #
  # It is also why the repository routes carry a static "_" segment rather than
  # spelling a slug as bare path segments: this glob claims every path from
  # three segments deep onwards, and would otherwise read
  # /docs/github.com/kemalcr/kemal as package "github.com" at version
  # "kemalcr". LuckyRouter tries static parts before dynamic ones, so "_" is
  # matched before :package_name is ever considered.
  #
  # The two segments are rejoined, so a URL reads the way a Crystal name does:
  #   /docs/kemal/1.6.0/Kemal/Config  ->  Kemal::Config
  get "/docs/:package_name/:version/:top_level/*:rest" do
    doc = DocQuery.new
      .preload_doc_versions
      .package_name(package_name)
      .first?

    # Held on the package rather than on the package and version together, so
    # that a link written without a version still reaches
    # `redirect_to_current_version` below instead of being sent to a
    # repository URL that has no row for it yet. An ambiguous name overrides
    # this either way: `resolve_bare_name` answers that case before it looks
    # at what is held.
    response = resolve_bare_name(package_name, !doc.nil?) do |slug|
      CrystalDocs::PackagePaths.type_path(slug, version, requested_path)
    end

    if response
      response
    elsif doc.nil?
      raise Lucky::RouteNotFoundError.new(context)
    else
      doc_version = doc.doc_versions.find { |v| v.version == version }

      if doc_version.nil?
        redirect_to_current_version(doc)
      else
        render_type(doc, doc_version, requested_path)
      end
    end
  end

  # The version segment does not name a version of this package. Usually that
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
