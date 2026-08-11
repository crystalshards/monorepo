# Port 80 exists to redirect human traffic to HTTPS. It is not part of
# certificate validation: Google validates a managed certificate by checking that
# the domain resolves publicly to this load balancer and that the certificate is
# attached to a target proxy whose forwarding rule serves 443. Port 80 is
# neither required for that nor an obstacle to it.
resource "google_compute_global_forwarding_rule" "http" {
  project = var.project_id
  name    = "${var.name_prefix}-http"

  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.address
  ip_protocol           = "TCP"
  port_range            = "80"
  target                = google_compute_target_http_proxy.http.id
}
