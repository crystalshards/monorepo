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

    storage_service = CrystalDocs::DocsStorageService.new

    doc_content = storage_service.fetch_doc_file(
      package_name: package_name,
      version: version,
      file_path: file
    )

    if doc_content.nil?
      html Docs::VersionNotFoundPage,
        doc: doc,
        doc_version: doc_version,
        file_path: file
    else
      increment_views(doc)

      # Fetch navigation structure
      nav_files = storage_service.list_doc_files(package_name, version)

      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        doc_content: doc_content,
        file_path: file,
        nav_files: nav_files
    end
  end

  private def increment_views(doc : Doc)
    SaveDoc.update!(doc, total_views: doc.total_views + 1)
  rescue
  end
end
