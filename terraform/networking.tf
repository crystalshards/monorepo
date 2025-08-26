# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false
  description             = "VPC network for CrystalShards cluster"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/16"
  network       = google_compute_network.vpc.name
  region        = var.region
  description   = "Subnet for CrystalShards GKE cluster"

  # Secondary IP ranges for pods and services
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/16"
  }

  # Enable private Google access
  private_ip_google_access = true
}

# Cloud Router for NAT gateway
resource "google_compute_router" "router" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

# NAT Gateway for outbound internet access from private nodes
resource "google_compute_router_nat" "nat" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall rules
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.cluster_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/16"]
  description   = "Allow internal communication within the cluster"
}

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