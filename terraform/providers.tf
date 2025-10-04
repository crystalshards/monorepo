# Data source for GCP client config
data "google_client_config" "default" {}

# Google Cloud provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Kubernetes provider - configured to use the GKE cluster
provider "kubernetes" {
  host                   = "https://${module.cluster.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
}

# kubectl provider - for managing K8s resources that kubernetes provider doesn't support well
provider "kubectl" {
  host                   = "https://${module.cluster.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  load_config_file       = false
}

# Helm provider - for deploying Helm charts
provider "helm" {
  kubernetes {
    host                   = "https://${module.cluster.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.cluster.cluster_ca_certificate)
  }
}
