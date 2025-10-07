variable "cluster_name" {
  description = "The name of the GKE cluster"
  type        = string
}

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy (git commit SHA or 'latest')"
  type        = string
  default     = "latest"
}
