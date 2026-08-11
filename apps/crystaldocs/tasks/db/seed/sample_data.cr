class Db::Seed::SampleData < LuckyTask::Task
  summary "Add sample database records helpful for development"

  # One pinned, real version per package. scripts/build_real_docs.sh builds
  # exactly these versions into object storage, so the two stay in lockstep:
  # the rows seeded here describe the documentation `make docs.real` produces.
  PACKAGES = [
    {
      name: "kemal", version: "1.6.0", released_at: 20.months.ago,
      description: "Lightning Fast, Super Simple web framework for Crystal.",
      repository_url: "https://github.com/kemalcr/kemal",
    },
    {
      name: "amber", version: "1.5.0", released_at: 12.months.ago,
      description: "A Crystal web framework that makes building applications fast, simple, and enjoyable.",
      repository_url: "https://github.com/amberframework/amber",
    },
    {
      name: "lucky", version: "1.5.0", released_at: 6.months.ago,
      description: "A full-featured Crystal web framework that catches bugs for you, runs incredibly fast, and helps you write code that lasts.",
      repository_url: "https://github.com/luckyframework/lucky",
    },
    {
      name: "granite", version: "0.23.4", released_at: 24.months.ago,
      description: "ORM for Crystal. Inspired by ActiveRecord and Ecto.",
      repository_url: "https://github.com/amberframework/granite",
    },
    {
      name: "jennifer", version: "0.13.0", released_at: 24.months.ago,
      description: "Active Record pattern implementation for Crystal with flexible query chainable builder and migration system.",
      repository_url: "https://github.com/imdrasil/jennifer.cr",
    },
    {
      name: "ameba", version: "1.6.4", released_at: 15.months.ago,
      description: "A static code analysis tool for Crystal.",
      repository_url: "https://github.com/crystal-ameba/ameba",
    },
    {
      name: "spectator", version: "0.12.4", released_at: 14.months.ago,
      description: "Feature-rich spec testing framework for Crystal inspired by RSpec.",
      repository_url: "https://github.com/icy-arctic-fox/spectator",
    },
    {
      name: "crystal-pg", version: "0.30.0", released_at: 10.months.ago,
      description: "PostgreSQL driver for Crystal.",
      repository_url: "https://github.com/will/crystal-pg",
    },
    {
      name: "crystal-redis", version: "2.9.1", released_at: 26.months.ago,
      description: "Full featured Redis client for Crystal.",
      repository_url: "https://github.com/stefanwille/crystal-redis",
    },
    {
      name: "jwt", version: "1.7.2", released_at: 16.months.ago,
      description: "JSON Web Token implementation in Crystal.",
      repository_url: "https://github.com/crystal-community/jwt",
    },
    {
      name: "spec-kemal", version: "1.3.0", released_at: 18.months.ago,
      description: "Easy testing for Kemal applications.",
      repository_url: "https://github.com/kemalcr/spec-kemal",
    },
  ]

  @found_docs = false
  @storage_warnings = 0

  def call
    puts "Seeding documentation entries..."

    PACKAGES.each { |package| sync_package(package) }

    if @storage_warnings > 0
      puts ""
      puts "WARNING: object storage was unreachable for #{@storage_warnings} version listing(s);"
      puts "         those versions are seeded as pending with zero counts."
      puts "         Start local services (make services) and re-run to reflect reality."
    end

    unless @found_docs
      puts ""
      puts "No generated documentation was found in object storage, so every"
      puts "version is seeded as pending. Run 'make docs.real' to build real"
      puts "documentation for these packages, then re-run 'make seed'."
    end

    puts "Done adding sample data"
  end

  # Creates the Doc row (and the curated version row) when missing, then
  # re-derives every version row of the package from object storage.
  private def sync_package(package) : Nil
    doc = find_or_create_doc(package)

    rows = DocVersionQuery.new.doc_id(doc.id).to_a
    unless rows.any? { |row| row.version == package[:version] }
      rows << SaveDocVersion.create!(
        doc_id: doc.id,
        version: package[:version],
        published_at: package[:released_at],
        build_status: "pending",
        storage_path: "#{package[:name]}/#{package[:version]}",
        file_count: 0,
        total_size: 0_i64
      )
    end

    documented = rows.count { |row| sync_version_row(package[:name], row) }

    puts "  #{package[:name]}: #{rows.size} version(s), #{documented} with documentation in storage"
  end

  private def find_or_create_doc(package) : Doc
    doc = DocQuery.new.package_name(package[:name]).first?
    return create_doc(package) if doc.nil?

    if doc.current_version == package[:version]
      doc
    else
      SaveDoc.update!(doc, current_version: package[:version], last_updated_at: Time.utc)
    end
  end

  private def create_doc(package) : Doc
    SaveDoc.create!(
      package_name: package[:name],
      current_version: package[:version],
      description: package[:description],
      repository_url: package[:repository_url],
      total_views: Random.rand(100..50000).to_i64,
      last_updated_at: Time.utc
    )
  end

  # Points one version row at the truth in object storage. Returns whether
  # generated documentation exists for it. A row claims success only when the
  # store answered and <package>/<version>/docs.json is actually there;
  # anything else is pending with zero counts, never an assumed success.
  private def sync_version_row(package_name : String, row : DocVersion) : Bool
    listing = storage_listing(package_name, row.version)
    @storage_warnings += 1 unless listing[:available]

    success = listing[:available] && listing[:json_exists]
    @found_docs = true if success

    # One artifact per version, the docs.json itself, so a documented version
    # holds exactly one file and its real byte size.
    status = success ? "success" : "pending"
    files = success ? 1 : 0
    bytes = success ? listing[:bytes] : 0_i64

    if row.build_status != status || row.file_count != files || row.total_size != bytes
      SaveDocVersion.update!(row, build_status: status, file_count: files, total_size: bytes)
    end

    success
  end

  # Reads <package>/<version>/docs.json from the docs bucket: whether the
  # store answered, whether the artifact is there, and its real byte size.
  # `available: false` means the store could not be reached, which says
  # nothing about whether the documentation exists.
  private def storage_listing(package_name : String, version : String) : NamedTuple(available: Bool, json_exists: Bool, bytes: Int64)
    key = "#{package_name}/#{version}/docs.json"

    begin
      content = CrystalStorage.docs.get(key)
      {available: true, json_exists: !content.nil?, bytes: content ? content.size.to_i64 : 0_i64}
    rescue CrystalStorage::Unavailable
      {available: false, json_exists: false, bytes: 0_i64}
    end
  end
end
