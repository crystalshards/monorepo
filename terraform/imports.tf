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
