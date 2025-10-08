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

# CrystalBits secrets
variable "crystalbits_resend_key" {
  description = "Resend API key for CrystalBits email functionality"
  type        = string
  sensitive   = true
}

# CrystalGigs secrets
variable "crystalgigs_resend_key" {
  description = "Resend API key for CrystalGigs email functionality"
  type        = string
  sensitive   = true
}

variable "crystalgigs_stripe_secret_key" {
  description = "Stripe secret key for CrystalGigs payment processing"
  type        = string
  sensitive   = true
}

variable "crystalgigs_stripe_publishable_key" {
  description = "Stripe publishable key for CrystalGigs payment processing"
  type        = string
  sensitive   = true
}
