variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
  default     = "crystalshards-cluster"
}

variable "image_tag" {
  description = "Docker image tag to deploy (git commit SHA, e.g., 'sha-abc123')"
  type        = string
  default     = "dev" # Use 'dev' for initial deployment, should be overridden in production
}
