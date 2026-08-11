class Docs::Type < BrowserAction
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
  # The two segments are rejoined, so a URL reads the way a Crystal name does:
  #   /docs/kemal/1.6.0/Kemal/Config  ->  Kemal::Config
  get "/docs/:package_name/:version/:top_level/*:rest" do
    doc = DocQuery.new
      .preload_doc_versions
      .package_name(package_name)
      .first?

    raise Lucky::RouteNotFoundError.new(context) if doc.nil?

    doc_version = doc.doc_versions.find { |v| v.version == version }

    if doc_version.nil?
      redirect_to_current_version(doc)
    else
      render_type(doc, doc_version)
    end
  end

  # The version segment does not name a version of this package. Usually that
  # means a link written without one, so send the reader to the same type in
  # the current version rather than dead-ending one segment from correct.
  private def redirect_to_current_version(doc : Doc)
    current = doc.current_version

    if current && current != version
      redirect to: "/docs/#{package_name}/#{current}/#{version}/#{requested_path}"
    else
      raise Lucky::RouteNotFoundError.new(context)
    end
  end

  private def render_type(doc : Doc, doc_version : DocVersion)
    document = CrystalDocs::DocsLoader.build.load(package_name, doc_version.version).document

    if document.nil?
      # Either the build produced nothing or storage is unreachable. The
      # version page already tells those apart for the reader, so defer to it
      # rather than inventing a second explanation here.
      #
      # This action deliberately never enqueues. With lazy generation any URL
      # that can commission a build is a spend endpoint, and a type path is
      # attacker shaped: /docs/pkg/1.0.0/Anything/At/All parses fine and
      # resolves to nothing. Without the index there is no way to tell an
      # invented path from a real type, so this does not pretend to; it hands
      # off to the version route, which enqueues for the version, which
      # genuinely is missing. Enqueue is keyed on the version and never on the
      # requested path, so ten thousand invented paths under one unbuilt
      # version still commission exactly one build.
      redirect to: "/docs/#{package_name}/#{doc_version.version}"
    else
      # The index is in hand, so an unknown path is known to be no type.
      type = document.find_type(requested_path.gsub('/', "::"))
      raise Lucky::RouteNotFoundError.new(context) if type.nil?

      html Docs::TypePage,
        doc: doc,
        doc_version: doc_version,
        document: document,
        type: type,
        linker: build_linker(doc_version, document)
    end
  end

  private def build_linker(doc_version : DocVersion, document : CrystalDocs::DocsDocument) : CrystalDocs::TypeLinker
    CrystalDocs::TypeLinker.new(
      package_name: package_name,
      version: doc_version.version,
      local_types: CrystalDocs::TypeLinker.local_names(document),
      dependency_index: CrystalDocs::DependencyIndex.for(package_name, doc_version.version)
    )
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
