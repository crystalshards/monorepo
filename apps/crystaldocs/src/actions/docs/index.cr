class Docs::Index < BrowserAction
  param page : Int32 = 1
  param query : String?

  get "/docs" do
    per_page = 20
    docs_query = DocQuery.new.preload_doc_versions

    if search_query = query
      docs_query = docs_query.package_name.ilike("%#{search_query}%")
    end

    docs_query = docs_query.last_updated_at.desc_order

    total_count = docs_query.select_count
    offset_value = (page - 1) * per_page

    paginated_docs = docs_query
      .limit(per_page)
      .offset(offset_value)

    html Docs::IndexPage,
      docs: paginated_docs,
      query: query,
      page: page,
      per_page: per_page,
      total_count: total_count
  end
end
