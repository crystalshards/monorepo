output "crystalshards_org_name_servers" {
  description = "Name servers for crystalshards.org zone"
  value       = google_dns_managed_zone.crystalshards_org.name_servers
}

output "crystaldocs_org_name_servers" {
  description = "Name servers for crystaldocs.org zone"
  value       = google_dns_managed_zone.crystaldocs_org.name_servers
}

output "crystalgigs_com_name_servers" {
  description = "Name servers for crystalgigs.com zone"
  value       = google_dns_managed_zone.crystalgigs_com.name_servers
}

output "crystalbits_org_name_servers" {
  description = "Name servers for crystalbits.org zone"
  value       = google_dns_managed_zone.crystalbits_org.name_servers
}

output "zones" {
  description = "All managed DNS zones"
  value = {
    crystalshards_org = {
      name         = google_dns_managed_zone.crystalshards_org.name
      dns_name     = google_dns_managed_zone.crystalshards_org.dns_name
      name_servers = google_dns_managed_zone.crystalshards_org.name_servers
    }
    crystaldocs_org = {
      name         = google_dns_managed_zone.crystaldocs_org.name
      dns_name     = google_dns_managed_zone.crystaldocs_org.dns_name
      name_servers = google_dns_managed_zone.crystaldocs_org.name_servers
    }
    crystalgigs_com = {
      name         = google_dns_managed_zone.crystalgigs_com.name
      dns_name     = google_dns_managed_zone.crystalgigs_com.dns_name
      name_servers = google_dns_managed_zone.crystalgigs_com.name_servers
    }
    crystalbits_org = {
      name         = google_dns_managed_zone.crystalbits_org.name
      dns_name     = google_dns_managed_zone.crystalbits_org.dns_name
      name_servers = google_dns_managed_zone.crystalbits_org.name_servers
    }
  }
}

output "a_records" {
  description = "Hostname to the address it resolves to, for confirming that all eight names were written and none kept the old value."
  value       = { for host, record in google_dns_record_set.a : host => one(record.rrdatas) }
}
