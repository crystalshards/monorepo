resource "google_compute_global_forwarding_rule" "https" {
  project = var.project_id
  name    = "${var.name_prefix}-https"

  # Must match the backend services. EXTERNAL_MANAGED on one side and EXTERNAL on
  # the other is rejected by the API.
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.address
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_target_https_proxy.https.id
}
