# The second database this suite writes to.
#
# crystaldocs owns doc_build_requests, doc_versions and docs; this app writes
# three distinct slices of them. It is the only process that knows whether a
# build started, finished or failed, so it writes the outcome columns of
# doc_build_requests and doc_versions over `DocsDatabase`. Until that existed
# no spec in this app had those tables at all: every write raised "relation
# doc_build_requests does not exist", the writer swallowed it, and the one
# thing the builder tells the documentation site went untested in both apps.
# That is how doc_versions.build_status stayed 'pending' for the entire
# catalogue without a single red spec.
#
# CrystalShards::CoreDocs::Registration is the second writer, added for the
# standard library: current_version, description and repository_url on docs,
# the same three columns `CrystalDocs::PackageRegistration` sets from a
# registry release for a shard. The standard library has no registry entry to
# set them from a reader's request, so this app sets them itself before the
# first build, which is why this app now writes columns on `docs` it never
# used to.
#
# The tables are created here rather than by running crystaldocs's migrations,
# which are not in this app's source and must not be. Only the columns this app
# reads or writes are defined, which is the same discipline the queries
# themselves follow: hand written SQL over a small, stable set of columns, so a
# schema change over there cannot silently retype anything here. The
# constraints that are copied are the ones the writes actually run into, namely
# NOT NULL on storage_path and the two unique indexes; a spec that plants a row
# has to plant a real one.
module DocsTestDatabase
  # Ordered so a TRUNCATE naming all three never depends on cascade order.
  TABLES = %w[doc_build_requests doc_versions docs]

  # One statement per element: the Postgres driver prepares every statement it
  # is given, and a prepared statement holds exactly one command.
  STATEMENTS = [
    <<-SQL,
    CREATE TABLE IF NOT EXISTS docs (
      id bigserial PRIMARY KEY,
      package_name text NOT NULL UNIQUE,
      current_version text,
      description text,
      repository_url text,
      total_views bigint NOT NULL DEFAULT 0,
      created_at timestamptz NOT NULL,
      updated_at timestamptz NOT NULL
    )
    SQL
    <<-SQL,
    CREATE TABLE IF NOT EXISTS doc_versions (
      id bigserial PRIMARY KEY,
      doc_id bigint NOT NULL REFERENCES docs (id) ON DELETE CASCADE,
      version text NOT NULL,
      published_at timestamptz NOT NULL,
      build_status text NOT NULL DEFAULT 'pending',
      storage_path text NOT NULL,
      created_at timestamptz NOT NULL,
      updated_at timestamptz NOT NULL,
      UNIQUE (doc_id, version)
    )
    SQL
    <<-SQL,
    CREATE TABLE IF NOT EXISTS doc_build_requests (
      id bigserial PRIMARY KEY,
      package_name text NOT NULL,
      version text NOT NULL,
      status text NOT NULL DEFAULT 'pending',
      requested_at timestamptz NOT NULL,
      started_at timestamptz,
      finished_at timestamptz,
      failed_at timestamptz,
      last_error text,
      attempts integer NOT NULL DEFAULT 0,
      job_id text,
      created_at timestamptz NOT NULL,
      updated_at timestamptz NOT NULL,
      UNIQUE (package_name, version)
    )
    SQL
  ]

  def self.prepare : Nil
    create_database
    STATEMENTS.each { |statement| DocsDatabase.exec(statement) }
  end

  def self.truncate : Nil
    DocsDatabase.exec("TRUNCATE TABLE #{TABLES.join(", ")} RESTART IDENTITY CASCADE")
  end

  # Same shape as `Avram::Migrator::Runner.create_db`, which cannot be used
  # here: it only ever creates `Avram.settings.database_to_migrate`, and this
  # app migrates its own database, not this one.
  private def self.create_database : Nil
    credentials = DocsDatabase.credentials

    DB.connect("#{credentials.connection_string}/#{Avram.settings.setup_database_name}") do |db|
      db.exec "CREATE DATABASE #{credentials.database}"
    end
  rescue ex : Exception
    # Two spec runs against the same server race here, and the loser must not
    # fail. Anything else is a real problem and is re-raised.
    raise ex unless ex.message.to_s.includes?("already exists")
  end
end

DocsTestDatabase.prepare
