# Compute. Gates the global external Application Load Balancer, the serverless
# NEGs and google_compute_managed_ssl_certificate, all owned by the edge module.
resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_on_destroy = var.disable_on_destroy
}
