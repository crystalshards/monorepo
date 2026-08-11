# Artifact Registry. Holds the docker-images repository that every Cloud Run
# service and Job pulls from.
resource "google_project_service" "artifactregistry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
