class DocQuery < Doc::BaseQuery
  # Search by package name or description
  def search(term : String?)
    return self unless term && !term.empty?

    package_name.ilike("%#{term}%")
      .or { |query| query.description.ilike("%#{term}%") }
  end

  # Order by last updated
  def recently_updated
    last_updated_at.desc_order
  end

  # Order by popularity
  def popular
    total_views.desc_order
  end

  # Only docs with at least one version
  def with_versions
    inner_join_doc_versions
  end

  # Only docs with successful builds
  def with_successful_builds
    inner_join_doc_versions.doc_versions.build_status.eq("success")
  end

  # Preload doc_versions relationship
  def preload_versions
    preload_doc_versions
  end
end
