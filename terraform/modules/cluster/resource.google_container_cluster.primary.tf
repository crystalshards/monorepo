# GKE Autopilot Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # Enable Autopilot mode for fully managed nodes
  enable_autopilot = true

  # Networking
  network    = var.network_name
  subnetwork = var.subnet_name

  # IP allocation for pods and services
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Note: resource_usage_export_config is not supported for Autopilot clusters
  # GCP automatically provides cost monitoring for Autopilot

  # Security configurations
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
}
