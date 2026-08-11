resource "google_secret_manager_secret" "secret_key_base" {
  for_each = local.lucky_services

  project   = var.project_id
  secret_id = "${each.key}-secret-key-base"

  labels = {
    app        = each.key
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
