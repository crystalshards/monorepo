# Certificate Manager. Enabled so certificate work has the API available
# without a second apply, even though the edge module currently uses the
# classic google_compute_managed_ssl_certificate on the compute API.
resource "google_project_service" "certificatemanager" {
  project = var.project_id
  service = "certificatemanager.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
