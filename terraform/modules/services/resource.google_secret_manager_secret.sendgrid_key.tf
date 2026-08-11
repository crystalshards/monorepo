# One mail key per service rather than one shared key, so revoking a
# compromised key takes one site down instead of all of them.
resource "google_secret_manager_secret" "sendgrid_key" {
  for_each = local.lucky_services

  project   = var.project_id
  secret_id = "${each.key}-sendgrid-key"

  labels = {
    app        = each.key
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
