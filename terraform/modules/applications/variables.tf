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
