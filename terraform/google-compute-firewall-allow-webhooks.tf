# Firewall rule for HTTPS webhooks
resource "google_compute_firewall" "allow_webhooks" {
  name    = "${var.cluster_name}-allow-webhooks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "9443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
  description   = "Allow HTTPS webhooks for operators"
}
