variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "image_tag" {
  description = <<-DESC
    Container image tag to create Cloud Run services and Jobs at. Always a git
    commit SHA.

    No default, on purpose. It used to default to "latest", and CI does not push
    a "latest" tag, so a plan run without this variable would resolve every
    image to a tag that does not exist and fail at create time with something
    that looks like a registry problem. Required means the plan fails on the
    missing variable instead, naming it.
  DESC
  type        = string
}

# Outbound email. Every app calls exit(1) at boot in production without its key,
# so these are start up dependencies rather than optional integrations. One key
# per service so revoking a compromised key takes one site down, not all of
# them. The literal string "unused" is the app's own documented value for
# running with outbound email switched off.
variable "crystalshards_sendgrid_key" {
  description = "SendGrid API key for CrystalShards"
  type        = string
  sensitive   = true
}

variable "crystaldocs_sendgrid_key" {
  description = "SendGrid API key for CrystalDocs"
  type        = string
  sensitive   = true
}

variable "crystalgigs_sendgrid_key" {
  description = "SendGrid API key for CrystalGigs"
  type        = string
  sensitive   = true
}

variable "crystalbits_sendgrid_key" {
  description = "SendGrid API key for CrystalBits"
  type        = string
  sensitive   = true
}

variable "docs_launcher_sendgrid_key" {
  description = "SendGrid API key for docs-launcher. It sends no mail, but it is built from the registry codebase and inherits that boot time requirement"
  type        = string
  sensitive   = true
}

# CrystalGigs payments
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
