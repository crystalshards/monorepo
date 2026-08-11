class Docs::Version < BrowserAction
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

    document = CrystalDocs::DocsLoader.build.load(package_name, version).document
    increment_views(doc) if document

    html Docs::VersionPage,
      doc: doc,
      doc_version: doc_version,
      document: document
  end

  private def increment_views(doc : Doc)
    SaveDoc.update!(doc, total_views: doc.total_views + 1)
  rescue
  end
end
