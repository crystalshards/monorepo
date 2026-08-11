# One A record per public hostname, apex and www, all pointing at the load
# balancer address.
#
# What these replace: each zone held a single apex A record pointing at
# 136.114.166.228, an address owned by nothing in this project, and no www record
# at all. Those four apex records exist in Cloud DNS but were never in terraform
# state, so they are adopted by the import blocks in terraform/imports.edge.tf and
# repointed here. The dead address does not survive the apply.
#
# The hostnames come from var.sites, the same value module.edge uses to build the
# certificates and the URL map host rules, so DNS cannot answer for a name the
# load balancer does not route, or miss one that it does.
resource "google_dns_record_set" "a" {
  for_each = local.a_records

  project      = var.project_id
  managed_zone = each.value
  name         = "${each.key}."
  type         = "A"
  ttl          = var.record_ttl
  rrdatas      = [var.load_balancer_ip]

  # The zones already exist and are unchanged, so this is ordering insurance
  # rather than a live dependency: a zone added later cannot be raced by its own
  # records.
  depends_on = [
    google_dns_managed_zone.crystalshards_org,
    google_dns_managed_zone.crystaldocs_org,
    google_dns_managed_zone.crystalgigs_com,
    google_dns_managed_zone.crystalbits_org,
  ]
}
