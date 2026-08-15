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
    # Left unset here on purpose: nil is what an untouched migrated row
    # looks like, and most examples render a version without caring what it
    # was built from. A spec proving reference resolution sets
    # `source_commit_sha` explicitly, through the setter Avram already
    # generates for every column, the same way callers already set
    # `build_status` and `storage_path` above.
  end
end
