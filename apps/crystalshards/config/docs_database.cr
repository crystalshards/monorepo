docs_database_name = "crystaldocs_#{LuckyEnv.environment}"

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
