# Development points at the real crystaldocs development database, because
# locally both apps run against one Postgres and the builder writing what the
# documentation site reads is the whole point of running them together.
#
# Test does NOT, and must not. crystaldocs_test belongs to the crystaldocs spec
# suite and to its migrations: two suites pointed at it truncate each other's
# rows between examples, and the tables this suite creates for itself are
# tables the other app's migrator then finds already present with no migration
# recorded. So the test name is derived from this app's own database, which
# means a spec run given a unique DATABASE_URL gets a unique docs database with
# it and cannot reach another suite's.
docs_database_name =
  if LuckyEnv.test?
    "#{AppDatabase.credentials.database}_docs"
  else
    "crystaldocs_#{LuckyEnv.environment}"
  end

DocsDatabase.configure do |settings|
  settings.credentials =
    if docs_url = ENV["DOCS_DATABASE_URL"]?
      Avram::Credentials.parse(docs_url)
    elsif LuckyEnv.production?
      # Nothing is guessed in production. The docs site can live on another
      # host under another role, and quietly pointing at this app's own server
      # would surface as "relation doc_build_requests does not exist" in a
      # worker log, where nobody is looking, while every docs page sat on a
      # pending build that had in fact already finished.
      raise "DOCS_DATABASE_URL is required. The docs build worker records build state in the crystaldocs database, and there is no safe default for where that database lives or which credentials reach it."
    else
      # Development and test run every app against one Postgres server with
      # one database per app, so this is this app's own connection pointed at
      # a different database. Reusing the credentials already configured
      # avoids introducing a second set for the same local server.
      app = AppDatabase.credentials

      Avram::Credentials.new(
        database: docs_database_name,
        hostname: app.hostname,
        username: app.username,
        password: app.password,
        port: app.port,
        query: app.query
      )
    end
end
