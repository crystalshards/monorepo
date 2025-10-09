# Managed DNS zone for crystalshards.org
resource "google_dns_managed_zone" "crystalshards_org" {
  name        = "crystalshards-org"
  dns_name    = "crystalshards.org."
  description = "DNS zone for CrystalShards package registry"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
