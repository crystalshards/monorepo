# One identity per application service. Nothing is shared, so a role granted to
# one app is never quietly inherited by another.
resource "google_service_account" "apps" {
  for_each = local.apps

  project      = var.project_id
  account_id   = each.key
  display_name = "Cloud Run service account for ${each.key}"
}
