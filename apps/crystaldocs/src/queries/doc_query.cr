class DocQuery < Doc::BaseQuery
  def search(term : String?)
    return self unless term && !term.empty?

    package_name.ilike("%#{term}%")
      .or(&.description.ilike("%#{term}%"))
  end

  def with_versions
    preload_doc_versions
  end

  def recently_updated
    last_updated_at.desc_order
  end

  def popular
    total_views.desc_order
  end

  def published
    current_version.is_not_nil
  end
end
