resource "google_secret_manager_secret_version" "database_url" {
  for_each = var.apps

  secret      = google_secret_manager_secret.database_url[each.key].id
  secret_data = local.database_urls[each.key]

  depends_on = [google_sql_user.apps]
}
