# Cloud Tasks. Backs the docs-builds queue that carries lazy documentation
# build requests from crystalshards to docs-launcher.
resource "google_project_service" "cloudtasks" {
  project = var.project_id
  service = "cloudtasks.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
