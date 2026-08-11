locals {
  # The connection string every consumer of this instance uses.
  #
  # Shape matters more than it looks. The host is left out of the authority so
  # that crystal-pg falls through to the "host" query parameter, which is where
  # the socket path goes: PQ::ConnInfo takes uri.hostname.presence first and
  # only then params["host"], so writing "localhost" in the authority would
  # silently win and send the connection to TCP. The path is the socket file
  # itself and not its directory, because PQ::Connection does
  # UNIXSocket.new(host) verbatim with no ".s.PGSQL.5432" appended unless the
  # value came from PGHOST.
  #
  # max_pool_size rides in the same query string. crystal-db reads its pool
  # options from the connection URI and defaults max_pool_size to 0, meaning
  # unlimited. Leaving it unset is what turns four autoscaling services into a
  # connection exhaustion incident on the first burst of real traffic.
  socket_path = "/cloudsql/${google_sql_database_instance.crystal_postgres.connection_name}/.s.PGSQL.5432"

  database_urls = {
    for app in var.apps :
    app => join("", [
      "postgres://",
      app,
      ":",
      random_password.apps[app].result,
      "@/",
      google_sql_database.apps[app].name,
      "?host=", local.socket_path,
      "&max_pool_size=", tostring(var.connection_pool_size),
    ])
  }
}
