resource "google_secret_manager_secret" "stripe_publishable_key" {
  project   = var.project_id
  secret_id = "crystalgigs-stripe-publishable-key"

  labels = {
    app        = "crystalgigs"
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
