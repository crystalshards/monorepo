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

# There are deliberately NO variables here for the Resend API keys or the Stripe
# keys. They are third party credentials, so terraform cannot generate them, and
# routing them through a variable would put them in CI, in the plan, and then in
# the state file in gs://crystalshards-org-terraform-state permanently. Reading
# them back with a data source lands them in state too, so that relocates the
# exposure rather than removing it.
#
# Terraform creates the Secret Manager containers and Cloud Run references them.
# The values are added out of band by an operator and never enter terraform:
#
#   gcloud secrets versions add <secret-id> --data-file=-
#
# See terraform/modules/services/resource.google_secret_manager_secret.*.tf for
# the full reasoning and the exact secret ids.

# Names, not values. This is the list of app slugs whose Resend secret CI has
# populated, so terraform knows which revisions may reference it. A revision
# pointing at a versionless secret never reaches Ready, and no site should be
# down because mail is unconfigured.
variable "mail_enabled_apps" {
  description = "App slugs whose Resend secret has a version. Empty until the keys exist; the two senders then raise on send rather than failing to boot"
  type        = set(string)
  default     = []
}
