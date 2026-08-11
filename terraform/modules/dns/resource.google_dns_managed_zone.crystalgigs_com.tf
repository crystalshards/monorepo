# Managed DNS zone for crystalgigs.com. See crystalshards_org for why dns_name is
# derived and why this zone must not be replaced.
resource "google_dns_managed_zone" "crystalgigs_com" {
  name        = "crystalgigs-com"
  dns_name    = "${var.sites["crystalgigs"].apex}."
  description = "DNS zone for CrystalGigs freelance marketplace"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
