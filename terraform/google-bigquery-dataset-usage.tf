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
