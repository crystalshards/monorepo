# Managed DNS zone for crystaldocs.org
resource "google_dns_managed_zone" "crystaldocs_org" {
  name        = "crystaldocs-org"
  dns_name    = "crystaldocs.org."
  description = "DNS zone for CrystalDocs documentation hosting"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
