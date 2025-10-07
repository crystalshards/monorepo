class Api::Docs::Versions::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/docs/:package_name/:version" do
    doc = DocQuery.new
      .package_name(package_name)
      .first?

    if doc.nil?
      head 404
    else
      doc_version = DocVersionQuery.new
        .doc_id(doc.id)
        .version(version)
        .first?

      if doc_version.nil?
        head 404
      else
        json({
          package_name: doc.package_name,
          version:      doc_version.version,
          published_at: doc_version.published_at,
          build_status: doc_version.build_status,
          storage_path: doc_version.storage_path,
          file_count:   doc_version.file_count,
          total_size:   doc_version.total_size,
          metadata:     doc_version.metadata,
          created_at:   doc_version.created_at,
        })
      end
    end
  end
end
