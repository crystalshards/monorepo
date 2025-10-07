variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
}

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy (git commit SHA, e.g., 'sha-abc123')"
  type        = string
  # No default - must be explicitly set to prevent accidental 'latest' deployments
}
