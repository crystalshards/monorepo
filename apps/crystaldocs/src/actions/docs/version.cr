class Docs::Version < BrowserAction
  param file : String = "index.html"

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

    fetch = CrystalDocs::DocsStorageService.new.fetch_doc_file(
      package_name: package_name,
      version: version,
      file_path: file
    )

    if doc_content = fetch.content
      increment_views(doc)

      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        doc_content: doc_content,
        file_path: file
    elsif fetch.store_answered?
      # Storage answered and the file is not there, so this version genuinely
      # has no such documentation.
      html Docs::VersionNotFoundPage,
        doc: doc,
        doc_version: doc_version,
        file_path: file
    else
      # Storage is unavailable. The package and the version both exist, so
      # render the page and say the content could not be loaded rather than
      # claiming the documentation does not exist.
      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        doc_content: nil,
        file_path: file
    end
  end

  private def increment_views(doc : Doc)
    SaveDoc.update!(doc, total_views: doc.total_views + 1)
  rescue
  end
end
