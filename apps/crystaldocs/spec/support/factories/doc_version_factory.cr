class DocVersionFactory < Avram::Factory
  def initialize
    # doc_versions carries a UNIQUE (doc_id, version) index, so two versions
    # built for the same doc must not share a version string. Avram's sequence
    # hands back "<name>-<n>", and the trailing counter becomes the patch
    # number so the default stays a real semver.
    semver = "1.0.#{sequence("doc-version").rpartition('-').last}"

    version semver
    published_at Time.utc
    build_status "success"
    storage_path "sample-package/#{semver}"
  end
end
