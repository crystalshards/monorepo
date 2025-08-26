# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # Autopilot mode for cost optimization and scale-to-zero
  enable_autopilot = var.enable_autopilot

  # Remove default node pool for standard clusters
  remove_default_node_pool = !var.enable_autopilot
  initial_node_count       = var.enable_autopilot ? null : 1

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

  # Enable shielded nodes
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
}

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

# BigQuery dataset for resource usage monitoring
resource "google_bigquery_dataset" "usage" {
  dataset_id                  = "gke_usage_metering"
  friendly_name               = "GKE Usage Metering"
  description                 = "Dataset for GKE cluster resource usage data"
  location                    = var.region
  default_table_expiration_ms = 2592000000 # 30 days

  labels = {
    env     = "production"
    project = "crystalshards"
  }
}