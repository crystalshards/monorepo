# Plants and reads the crystaldocs rows this app writes.
#
# Raw SQL rather than factories, and deliberately so: the models for these
# tables live in the other app and this app has none, which is the same reason
# every production query against them is hand written. A spec that planted rows
# through an Avram model would be asserting against a schema this app invented
# instead of the one crystaldocs actually has.
module DocsRows
  # A registered version, exactly as `CrystalDocs::PackageRegistration` writes
  # it: the docs row, then the version row, pending, with storage_path naming
  # where the artifact would go whether or not anything is there.
  def self.register(
    package_name : String,
    version : String,
    build_status : String = "pending",
    commit_sha : String? = nil,
  ) : Nil
    now = Time.utc

    DocsDatabase.exec(<<-SQL, package_name, now)
      INSERT INTO docs (package_name, created_at, updated_at)
      VALUES ($1, $2, $2)
      ON CONFLICT (package_name) DO NOTHING
      SQL

    # published_at is a real, NOT NULL column on doc_versions: PackageRegistration
    # sets it from the registry release's own timestamp. This helper has no
    # release to read one from, so it uses `now`; nothing plants a row through
    # this path and then asserts on published_at.
    DocsDatabase.exec(<<-SQL, package_name, version, build_status, "#{package_name}/#{version}", commit_sha, now)
      INSERT INTO doc_versions
        (doc_id, version, published_at, build_status, storage_path, source_commit_sha, created_at, updated_at)
      SELECT id, $2, $6, $3, $4, $5, $6, $6 FROM docs WHERE package_name = $1
      ON CONFLICT (doc_id, version) DO NOTHING
      SQL
  end

  # The row a reader's request creates, which most of the catalogue does not
  # have. Written separately from `register` so a spec can exercise a build the
  # registry indexer commissioned, where doc_versions is the only row there is.
  def self.request(package_name : String, version : String, status : String = "pending") : Nil
    now = Time.utc

    DocsDatabase.exec(<<-SQL, package_name, version, status, now)
      INSERT INTO doc_build_requests
        (package_name, version, status, requested_at, attempts, created_at, updated_at)
      VALUES ($1, $2, $3, $4, 1, $4, $4)
      ON CONFLICT (package_name, version) DO NOTHING
      SQL
  end

  def self.version_status(package_name : String, version : String) : String
    DocsDatabase.query_one(
      <<-SQL,
      SELECT v.build_status
      FROM doc_versions v
      JOIN docs d ON d.id = v.doc_id
      WHERE d.package_name = $1 AND v.version = $2
      SQL
      package_name, version, as: String
    )
  end

  def self.request_status(package_name : String, version : String) : String
    DocsDatabase.query_one(
      "SELECT status FROM doc_build_requests WHERE package_name = $1 AND version = $2",
      package_name, version, as: String
    )
  end

  # The columns crystaldocs reads to decide what to show and when it may queue a
  # rebuild, returned together so a spec asserts on the whole outcome rather
  # than on the status string alone.
  record RequestOutcome,
    status : String,
    started_at : Time?,
    finished_at : Time?,
    failed_at : Time?,
    last_error : String?

  def self.request_outcome(package_name : String, version : String) : RequestOutcome
    status, started_at, finished_at, failed_at, last_error = DocsDatabase.query_one(
      <<-SQL,
      SELECT status, started_at, finished_at, failed_at, last_error
      FROM doc_build_requests
      WHERE package_name = $1 AND version = $2
      SQL
      package_name, version, as: {String, Time?, Time?, Time?, String?}
    )

    RequestOutcome.new(
      status: status,
      started_at: started_at,
      finished_at: finished_at,
      failed_at: failed_at,
      last_error: last_error
    )
  end

  # Makes the doc_versions write, and only that write, fail at the database.
  #
  # A CHECK constraint rather than a stub, because what has to be proved is that
  # Postgres rolling back the second statement takes the first one with it. A
  # fake writer proves nothing about a transaction.
  def self.refusing_doc_version_writes(&)
    DocsDatabase.exec(
      "ALTER TABLE doc_versions ADD CONSTRAINT refuse_writes CHECK (build_status = 'pending')"
    )

    begin
      yield
    ensure
      DocsDatabase.exec("ALTER TABLE doc_versions DROP CONSTRAINT refuse_writes")
    end
  end
end
