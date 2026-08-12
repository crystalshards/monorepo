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

# Names, not values. The list of git hosts whose discovery credential CI has
# populated, so terraform knows which token env vars the discovery Job may
# reference. A Cloud Run execution pointing at a versionless secret never starts,
# and no host should block a sweep of the hosts that are configured.
#
# There is deliberately no variable here for a host token itself, for the same
# reason there is none for the Resend or Stripe keys. See the comment above.
#
# The sweep's two bounded run knobs, discovery_max_pages and
# discovery_timeout_seconds, are deliberately NOT surfaced here. They have
# defaults and validation in modules/services/variables.tf, nothing outside
# terraform sets them, and a root variable restating a module default is the
# second source for one value that this configuration keeps warning about.
variable "discovery_enabled_hosts" {
  description = "Git hosts whose discovery credential has a version, as Discovery::CrawlRunner::HOSTS names them. Empty until the tokens exist; the sweep then reports every host as skipped and indexes nothing"
  type        = set(string)
  default     = []
}
