# Terraform variables for CrystalShards deployment
# GCP Project configuration
project_id = "crystalshards-org"
region     = "us-central1"

# Cluster configuration
cluster_name = "crystalshards-cluster"

# Docker image tag (override with -var="image_tag=sha-xxxxx" in CI/CD)
image_tag = "dev"
