# Firewall rule to allow HTTP and HTTPS traffic to the cluster
resource "google_compute_firewall" "allow_http_https" {
  name    = "${var.cluster_name}-allow-http-https"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]
  description   = "Allow HTTP and HTTPS traffic to nginx-ingress"
}
