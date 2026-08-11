# Managed DNS zone for crystalshards.org.
#
# dns_name is derived rather than written out so this zone and the A records,
# certificates and URL map host rules all read the same domain from one place.
# The rendered value is unchanged, so this does not plan a diff. It must stay
# unchanged: dns_name is immutable, and replacing this zone would issue new
# nameservers and break the delegation already set at the registrar.
resource "google_dns_managed_zone" "crystalshards_org" {
  name        = "crystalshards-org"
  dns_name    = "${var.sites["crystalshards"].apex}."
  description = "DNS zone for CrystalShards package registry"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
