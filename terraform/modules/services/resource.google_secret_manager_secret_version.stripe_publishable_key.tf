resource "google_secret_manager_secret_version" "stripe_publishable_key" {
  secret      = google_secret_manager_secret.stripe_publishable_key.id
  secret_data = var.crystalgigs_stripe_publishable_key
}
