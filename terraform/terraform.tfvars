# Terraform variables for CrystalShards deployment
# GCP Project configuration
project_id = "crystalshards-org"
region     = "us-central1"

# Cluster configuration
cluster_name = "crystalshards-cluster"

# Docker image tag (override with -var="image_tag=sha-xxxxx" in CI/CD)
image_tag = "latest"

# Application secrets (set to placeholder values for deployment)
crystalbits_resend_key             = "unused"
crystalgigs_resend_key             = "unused"
crystalgigs_stripe_secret_key      = "unused"
crystalgigs_stripe_publishable_key = "unused"
