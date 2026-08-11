# Managed DNS zone for crystaldocs.org. See crystalshards_org for why dns_name is
# derived and why this zone must not be replaced.
resource "google_dns_managed_zone" "crystaldocs_org" {
  name        = "crystaldocs-org"
  dns_name    = "${var.sites["crystaldocs"].apex}."
  description = "DNS zone for CrystalDocs documentation hosting"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
