variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region the Cloud Run services run in. The serverless NEGs must be created in the same region as the services they point at."
  type        = string
}

variable "sites" {
  description = <<-EOT
    The public sites, keyed by Cloud Run service key. Both apex and www are
    supplied already derived, by the caller, so that this module and modules/dns
    cannot disagree about which hostnames exist.

    dns_zone is unused here. The shape is shared with modules/dns deliberately:
    one value is passed to both modules, so there is no second site list that
    can fall out of step with this one.
  EOT
  type = map(object({
    apex     = string
    www      = string
    dns_zone = string
  }))

  validation {
    condition     = length(var.sites) > 0
    error_message = "At least one site is required, otherwise the load balancer has no backend and no certificate."
  }
}

variable "service_names" {
  description = "Cloud Run service name per site key, from module.services.service_names. A site with no matching service fails at plan rather than producing a load balancer pointed at nothing."
  type        = map(string)
}

variable "default_site" {
  description = "Site key used for requests whose Host header matches none of the configured hostnames, for example a request sent straight to the load balancer IP."
  type        = string
  default     = "crystalshards"
}

variable "name_prefix" {
  description = "Prefix for every resource name this module creates."
  type        = string
  default     = "crystal-edge"
}
