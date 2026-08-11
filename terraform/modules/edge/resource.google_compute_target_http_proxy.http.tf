resource "google_compute_target_http_proxy" "http" {
  project = var.project_id
  name    = "${var.name_prefix}-http"
  url_map = google_compute_url_map.http_redirect.id
}
