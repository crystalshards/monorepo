resource "google_service_account" "warm_popular_docs" {
  project      = var.project_id
  account_id   = "warm-popular-docs"
  display_name = "Documentation warming identity"
}
