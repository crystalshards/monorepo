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
  value = {
    "crystalshards.org" = module.dns.crystalshards_org_name_servers
    "crystaldocs.org"   = module.dns.crystaldocs_org_name_servers
    "crystalgigs.com"   = module.dns.crystalgigs_com_name_servers
    "crystalbits.org"   = module.dns.crystalbits_org_name_servers
  }
}
