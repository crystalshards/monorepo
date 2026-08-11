variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "sites" {
  description = <<-EOT
    The public sites, keyed by Cloud Run service key, with apex and www supplied
    already derived by the caller and the Cloud DNS managed zone each belongs to.

    The same value is passed to module.edge. That is the point: one site list
    feeds the certificates, the URL map host rules and these records, so they
    cannot drift into disagreeing about which hostnames exist.
  EOT
  type = map(object({
    apex     = string
    www      = string
    dns_zone = string
  }))
}

variable "load_balancer_ip" {
  description = "Address every A record points at, from module.edge.load_balancer_ip."
  type        = string
}

variable "record_ttl" {
  description = <<-EOT
    TTL in seconds for the A records.

    300 is a cutover value, not the intended steady state. It is deliberately low
    so a mistake during the move off the dead address can be corrected in minutes
    instead of hours. Follow-up once all eight hostnames are verified serving and
    their certificates are ACTIVE: raise this to a normal value, 3600 or higher.
  EOT
  type        = number
  default     = 300
}
