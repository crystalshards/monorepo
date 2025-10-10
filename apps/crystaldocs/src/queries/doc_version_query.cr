class DocVersionQuery < DocVersion::BaseQuery
  # Find versions for a specific doc
  def for_doc(doc : Doc)
    doc_id(doc.id)
  end

  def for_doc_id(id : Int64)
    doc_id(id)
  end

  # Order by version number (semantic versioning)
  def latest_first
    published_at.desc_order
  end

  # Only successful builds
  def successful
    build_status("success")
  end

  # Only failed builds
  def failed
    build_status("failed")
  end

  # Only pending builds
  def pending
    build_status("pending")
  end

  # Find by version string
  def version_number(v : String)
    version(v)
  end

  # Preload the doc relationship
  def preload_doc
    preload_doc
  end
end
