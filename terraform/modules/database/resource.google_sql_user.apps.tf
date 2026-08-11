# One login role per application, owning that application's database.
#
# Two services legitimately read a second database: crystalshards writes build
# state into crystaldocs, and crystaldocs reads the registry out of
# crystalshards. They do that as the owning role for the database they are
# visiting, using that database's own connection string, rather than as their
# own role with cross database grants layered on. That keeps table ownership
# and privileges exactly where the migrations put them.
resource "google_sql_user" "apps" {
  for_each = var.apps

  project  = var.project_id
  name     = each.key
  instance = google_sql_database_instance.crystal_postgres.name
  password = random_password.apps[each.key].result
}
