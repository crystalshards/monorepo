class Api::Docs::Index < ApiAction
  include Api::Auth::SkipRequireAuthToken

  param page : Int32 = 1
  param per_page : Int32 = 20
  param query : String?

  get "/api/docs" do
    docs_query = DocQuery.new
      .preload_doc_versions
      .last_updated_at.desc_order

    if search_query = query
      docs_query = docs_query.package_name.ilike("%#{search_query}%")
    end

    total_count = docs_query.select_count
    offset_value = (page - 1) * per_page

    paginated_docs = docs_query
      .limit(per_page)
      .offset(offset_value)

    json({
      docs: paginated_docs.map do |doc|
        {
          package_name:    doc.package_name,
          current_version: doc.current_version,
          description:     doc.description,
          repository_url:  doc.repository_url,
          total_views:     doc.total_views,
          last_updated_at: doc.last_updated_at,
          created_at:      doc.created_at,
          updated_at:      doc.updated_at,
        }
      end,
      meta: {
        page:     page,
        per_page: per_page,
        total:    total_count,
      },
    })
  end
end
