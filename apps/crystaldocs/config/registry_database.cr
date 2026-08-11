registry_database_name = "crystalshards_#{LuckyEnv.environment}"
registry_url = ENV["REGISTRY_DATABASE_URL"]?

registry_credentials =
  if registry_url
    Avram::Credentials.parse(registry_url)
  elsif LuckyEnv.production?
    # No credential is invented for production. The registry can live on
    # another host under another role, and quietly pointing at this app's own
    # server would surface as "relation shards does not exist" on a docs page,
    # which reads like a bug in the page rather than missing configuration.
    nil
  else
    # Development and test run every app against one Postgres server with one
    # database per app, so the registry is this app's own connection pointed
    # at a different database. Reusing the credentials already configured
    # avoids introducing a second set for the same local server.
    app = AppDatabase.credentials

    Avram::Credentials.new(
      database: registry_database_name,
      hostname: app.hostname,
      username: app.username,
      password: app.password,
      port: app.port,
      query: app.query
    )
  end

RegistryDatabase.configure do |settings|
  # Habitat wants a value whether or not anything will ever connect through
  # it. `void` is the "no connection is made" credential, and nothing reaches
  # the database while `configured?` is false.
  settings.credentials = registry_credentials || Avram::Credentials.void
end

RegistryDatabase.configured = !registry_credentials.nil?

unless RegistryDatabase.configured?
  # Deliberately a warning and not a raise. Dependency requirements only
  # decide whether a type name in a signature becomes a link, so an
  # unconfigured registry costs cross package links and nothing else. Taking
  # the whole documentation site down over link enrichment is a worse failure
  # than the one it would prevent. Said once, at boot, so the degraded mode is
  # visible rather than discovered.
  Log.for("crystaldocs.registry").warn do
    "REGISTRY_DATABASE_URL is not set. Dependency requirements and declared Crystal versions cannot be read, so cross package type names will render as plain text instead of links. Documentation itself is unaffected."
  end
end
