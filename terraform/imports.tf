# Import blocks for existing resources
# These will import existing GCP resources into Terraform state

# Import existing VPC network
import {
  to = google_compute_network.vpc
  id = "projects/waldrip-net/global/networks/crystalshards-cluster-vpc"
}

# Import existing BigQuery dataset
import {
  to = google_bigquery_dataset.usage
  id = "projects/waldrip-net/datasets/gke_usage_metering"
}

# Import existing subnet
import {
  to = google_compute_subnetwork.subnet
  id = "projects/waldrip-net/regions/us-central1/subnetworks/crystalshards-cluster-subnet"
}

# Import existing router
import {
  to = google_compute_router.router
  id = "projects/waldrip-net/regions/us-central1/routers/crystalshards-cluster-router"
}

# Import existing firewall rules
import {
  to = google_compute_firewall.allow_internal
  id = "projects/waldrip-net/global/firewalls/crystalshards-cluster-allow-internal"
}

import {
  to = google_compute_firewall.allow_webhooks
  id = "projects/waldrip-net/global/firewalls/crystalshards-cluster-allow-webhooks"
}

# Import existing Router NAT
import {
  to = google_compute_router_nat.nat
  id = "waldrip-net/us-central1/crystalshards-cluster-router/crystalshards-cluster-nat"
}
