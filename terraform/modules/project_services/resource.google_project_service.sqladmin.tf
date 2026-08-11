# Cloud SQL Admin. Creates and manages the crystal-postgres instance, and
# mints the ephemeral certificates the Cloud Run Cloud SQL socket connects with.
resource "google_project_service" "sqladmin" {
  project = var.project_id
  service = "sqladmin.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
