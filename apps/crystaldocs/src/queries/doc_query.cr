class DocQuery < Doc::BaseQuery
  def search(term : String?)
    return self unless term && !term.empty?

    package_name.ilike("%#{term}%")
      .or(&.description.ilike("%#{term}%"))
  end

  def with_versions
    preload_doc_versions
  end

  # last_updated_at records when documentation was last built, so a package
  # that has never been built has none. Postgres sorts NULLs first under DESC,
  # which put every package somebody had merely asked for at the top of a list
  # of the most recently updated. Nulls last: never built is not recent.
  def recently_updated
    last_updated_at.desc_order(:nulls_last)
  end

  def popular
    total_views.desc_order
  end

  def published
    current_version.is_not_nil
  end
end
