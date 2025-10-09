class Home::Index < BrowserAction
  get "/" do
    total_packages = DocQuery.new.select_count
    total_versions = DocVersionQuery.new.select_count

    recent_docs = DocQuery.new
      .preload_doc_versions
      .last_updated_at.desc_order
      .limit(6)

    popular_docs = DocQuery.new
      .preload_doc_versions
      .total_views.desc_order
      .limit(6)

    html Home::IndexPage,
      total_packages: total_packages,
      total_versions: total_versions,
      recent_docs: recent_docs,
      popular_docs: popular_docs
  end
end
