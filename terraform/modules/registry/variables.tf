variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region the repository lives in. Deliberately the same region as the Cloud Run services that pull from it, so an image pull is not a cross region fetch on every cold start"
  type        = string
}
