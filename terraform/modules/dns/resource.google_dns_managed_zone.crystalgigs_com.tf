# Managed DNS zone for crystalgigs.com
resource "google_dns_managed_zone" "crystalgigs_com" {
  name        = "crystalgigs-com"
  dns_name    = "crystalgigs.com."
  description = "DNS zone for CrystalGigs freelance marketplace"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
