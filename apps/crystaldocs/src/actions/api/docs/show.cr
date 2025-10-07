class Api::Docs::Show < ApiAction
  include Api::Auth::SkipRequireAuthToken

  get "/api/docs/:package_name" do
    doc = DocQuery.new
      .preload_doc_versions
      .package_name(package_name)
      .first?

    if doc.nil?
      head 404
    else
      json({
        package_name:    doc.package_name,
        current_version: doc.current_version,
        description:     doc.description,
        repository_url:  doc.repository_url,
        total_views:     doc.total_views,
        last_updated_at: doc.last_updated_at,
        created_at:      doc.created_at,
        updated_at:      doc.updated_at,
        versions:        doc.doc_versions.map do |version|
          {
            version:      version.version,
            published_at: version.published_at,
            build_status: version.build_status,
            storage_path: version.storage_path,
            file_count:   version.file_count,
            total_size:   version.total_size,
            created_at:   version.created_at,
          }
        end,
      })
    end
  end
end
