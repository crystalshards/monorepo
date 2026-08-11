# Port 80 exists for two reasons: to 301 human traffic to HTTPS, and because
# Google managed certificate validation is served through this frontend. Removing
# it would leave the certificates stuck in PROVISIONING.
resource "google_compute_global_forwarding_rule" "http" {
  project = var.project_id
  name    = "${var.name_prefix}-http"

  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http.id
}
