# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # Using standard GKE cluster (not Autopilot) for more control
  # enable_autopilot = false  # Disabled for now due to conflicts

  # Remove default node pool immediately (we create our own)
  remove_default_node_pool = true
  initial_node_count       = 1

  # Networking
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  # Enable network policy for security
  network_policy {
    enabled = true
  }

  # Enable Workload Identity for secure pod-to-GCP service communication
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Resource usage export for cost monitoring
  resource_usage_export_config {
    enable_network_egress_metering       = true
    enable_resource_consumption_metering = true
    bigquery_destination {
      dataset_id = google_bigquery_dataset.usage.dataset_id
    }
  }

  # Addons
  addons_config {
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
  }

  # Security configurations
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Enable private nodes for security
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Note: node_config is set in the node pool resource

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
}
