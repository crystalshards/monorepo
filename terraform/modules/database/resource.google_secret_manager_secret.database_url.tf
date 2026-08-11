# One secret per database holding its full connection string. Cloud Run reads
# these as env vars, so nothing ever assembles a URL from parts at runtime and
# there is exactly one place a credential can be rotated.
resource "google_secret_manager_secret" "database_url" {
  for_each = var.apps

  project   = var.project_id
  secret_id = "${each.key}-database-url"

  labels = {
    app        = each.key
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
