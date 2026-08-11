# Cloud Run. Serves all five services and runs the docs-build and migration
# Jobs.
resource "google_project_service" "run" {
  project = var.project_id
  service = "run.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
