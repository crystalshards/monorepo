# Cloud DNS. Gates the four managed zones and their record sets.
resource "google_project_service" "dns" {
  project = var.project_id
  service = "dns.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
