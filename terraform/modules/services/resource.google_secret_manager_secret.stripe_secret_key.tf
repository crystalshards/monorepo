resource "google_secret_manager_secret" "stripe_secret_key" {
  project   = var.project_id
  secret_id = "crystalgigs-stripe-secret-key"

  labels = {
    app        = "crystalgigs"
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
