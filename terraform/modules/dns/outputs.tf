# All outputs are keyed by site slug, the same key as local.sites at root, so a
# caller can label them with a hostname without writing one out again.

output "zones" {
  description = "All managed DNS zones, by site key."
  value = {
    for slug, zone in local.zones_by_site : slug => {
      name         = zone.name
      dns_name     = zone.dns_name
      name_servers = zone.name_servers
    }
  }
}

output "name_servers" {
  description = "Site key to the zone's delegated name servers. These are already set at the registrar and must not change."
  value       = { for slug, zone in local.zones_by_site : slug => zone.name_servers }
}

output "a_records" {
  description = "Hostname to the address it resolves to, for confirming all eight names were written and none kept the old value."
  value       = { for host, record in google_dns_record_set.a : host => one(record.rrdatas) }
}
