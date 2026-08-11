# Data source for GCP client config
data "google_client_config" "default" {}

# Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
}
