# One database per application. Named for the app, no environment suffix: this
# instance only ever holds production.
resource "google_sql_database" "apps" {
  for_each = var.apps

  project   = var.project_id
  name      = each.key
  instance  = google_sql_database_instance.crystal_postgres.name
  charset   = "UTF8"
  collation = "en_US.UTF8"
}
