# Managed DNS zone for the crystalbits site. See crystalshards_org for why
# dns_name is derived and why this zone must not be replaced.
resource "google_dns_managed_zone" "crystalbits_org" {
  name        = "crystalbits-org"
  dns_name    = "${var.sites["crystalbits"].apex}."
  description = "DNS zone for CrystalBits code snippets"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
