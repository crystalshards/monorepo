# Root outputs - aggregates outputs from all modules

# General outputs
output "region" {
  description = "GCP region"
  value       = var.region
}

output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

# DNS outputs
output "dns_zones" {
  description = "Cloud DNS managed zones with name servers"
  value       = module.dns.zones
}

output "dns_name_servers" {
  description = "DNS name servers for each domain"
  value       = { for slug, site in local.sites : site.apex => module.dns.name_servers[slug] }
}

# trycrystal outputs
#
# trycrystal_runner_service is read by the deploy's release job, which rolls
# the runner's image alongside the five public services. It is a raw string
# rather than part of cloud_run_services because the runner must never sit
# behind the load balancer.
output "trycrystal_runner_service" {
  description = "Name of the trycrystal runner Cloud Run service, for the release job's image roll"
  value       = module.services.trycrystal_runner_service
}

# The apex hostnames whose services hold a database. The deploy's smoke job
# asserts services.database == healthy only for these: trycrystal.org serves
# with no database at all, and demanding a healthy database of it would fail
# every deploy of a site that is working as designed.
output "database_backed_hostnames" {
  description = "Apex hostnames of the database backed sites, for the deploy smoke test's per-host health assertion"
  value       = [for slug in local.database_apps : local.sites[slug].apex]
}
