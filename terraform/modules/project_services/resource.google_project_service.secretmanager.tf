# Secret Manager. Holds every generated database password, connection string
# and application key. Cloud Run reads them at revision start.
resource "google_project_service" "secretmanager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
