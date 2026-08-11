class Docs::Version < BrowserAction
  include Docs::LazyBuild

  # The package overview: README, top level API, and the sidebar that leads
  # into individual types. Everything is rendered by us from the package's
  # docs.json, so no shard-authored HTML is ever served from this origin.
  get "/docs/:package_name/:version" do
    doc = DocQuery.new
      .preload_doc_versions
      .package_name(package_name)
      .first?

    if doc.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    doc_version = doc.doc_versions.find { |v| v.version == version }

    if doc_version.nil?
      raise Lucky::RouteNotFoundError.new(context)
    end

    # Documentation is built the first time someone asks for a version, so
    # three outcomes are possible here and they are not interchangeable.
    #
    # All three render the same overview page. The version switcher and the
    # build badge are how a reader moves between versions and learns that a
    # build failed, so they belong on the page whatever the outcome; routing
    # a missing artifact to a separate page took both away.
    result = CrystalDocs::DocsLoader.build.load(package_name, version)

    if document = result.document
      increment_views(doc)

      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        document: document,
        build_request: nil
    elsif result.store_answered?
      # Storage answered and holds nothing, or holds something unparseable.
      # Either way this version needs building. Enqueue at most one, keyed on
      # the version rather than on anything from the URL, and show the reader
      # what is happening.
      #
      # Never build inline: a build clones a repository and compiles third
      # party code, so doing it in the request would hold the connection for
      # minutes and hand any visitor a denial of service for the price of a
      # few cold URLs.
      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        document: nil,
        build_request: request_build(doc, doc_version)
    else
      # Storage never answered. Whether documentation exists is unknown, and
      # a build cannot fix a store that is down, so nothing is queued.
      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        document: nil,
        build_request: nil
    end
  end

  private def increment_views(doc : Doc)
    SaveDoc.update!(doc, total_views: doc.total_views + 1)
  rescue
  end
end
