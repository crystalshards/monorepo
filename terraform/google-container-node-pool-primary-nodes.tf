# Standard node pool (only if not using Autopilot)
resource "google_container_node_pool" "primary_nodes" {
  count      = var.enable_autopilot ? 0 : 1
  name       = "${var.cluster_name}-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = var.node_count

  # Auto-scaling configuration
  autoscaling {
    min_node_count = 0 # Enable scale to zero
    max_node_count = 10
  }

  # Node configuration
  node_config {
    preemptible  = var.preemptible
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb

    # Scopes for node access
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    # Labels for cost tracking
    labels = {
      env     = "production"
      project = "crystalshards"
    }

    # Shielded nodes
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  # Upgrade settings
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
