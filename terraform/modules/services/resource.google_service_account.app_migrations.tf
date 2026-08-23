# One identity per schema migration Job, separate from the service identity of
# the same name.
#
# It would be less typing to reuse the app's own service account here, and it
# would also hand a migration the app's buckets, its queue and its second
# database. A migration needs to open one database and nothing else, so it gets
# an identity that can do exactly that: roles/cloudsql.client, an accessor
# binding on its own connection string secret, and no third grant.
resource "google_service_account" "app_migrations" {
  for_each = local.database_apps

  project      = var.project_id
  account_id   = "${each.key}-migrate"
  display_name = "Schema migration Job identity for ${each.key}"
}
