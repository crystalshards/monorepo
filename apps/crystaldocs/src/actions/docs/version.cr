class Docs::Version < BrowserAction
  # Support wildcard path for deep linking to specific doc pages
  # Example: /docs/lucky/1.0.0/guides/getting-started.html
  # When no file path is specified, defaults to index.html
  get "/docs/:package_name/:version/*:file_path" do
    render_documentation(package_name, version, file_path || "index.html")
  end

  private def render_documentation(package_name : String, version : String, file_path : String)
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
      file_path: file_path
    )

    if doc_content.nil?
      html Docs::VersionNotFoundPage,
        doc: doc,
        doc_version: doc_version,
        file_path: file_path
    else
      increment_views(doc)

      # Fetch navigation structure
      nav_files = storage_service.list_doc_files(package_name, version)

      html Docs::VersionPage,
        doc: doc,
        doc_version: doc_version,
        doc_content: doc_content,
        file_path: file_path,
        nav_files: nav_files
    end
  end

  private def increment_views(doc : Doc)
    SaveDoc.update!(doc, total_views: doc.total_views + 1)
  rescue
  end
end
