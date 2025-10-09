# Managed DNS zone for crystalbits.org
resource "google_dns_managed_zone" "crystalbits_org" {
  name        = "crystalbits-org"
  dns_name    = "crystalbits.org."
  description = "DNS zone for CrystalBits code snippets"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
