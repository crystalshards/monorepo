# Managed DNS zone for the trycrystal site.
#
# dns_name is derived from local.sites rather than written out, so this zone
# and the A records, certificates and URL map host rules all read it from one
# place. The rendered value is "trycrystal.org.", and the zone name follows the
# existing <domain-with-dashes> pattern the other four zones use.
#
# Unlike the other four, this zone is brand new: it has no state to preserve
# and no registrar delegation yet. Until the registrar is pointed at the
# nameservers this zone issues (terraform output dns_name_servers), nothing
# under trycrystal.org resolves and the managed certificate for it stays
# PROVISIONING. That is expected. The ordering that is NOT safe is publishing
# the DNSSEC DS record at the registrar before the delegation is live and
# confirmed resolving: a DS that does not match the serving zone breaks the
# entire domain with SERVFAIL, not just the new records. Delegate first,
# confirm, then publish the DS. The full sequence is written out in
# apps/trycrystal/REGISTRATION.md.
resource "google_dns_managed_zone" "trycrystal_org" {
  name        = "trycrystal-org"
  dns_name    = "${var.sites["trycrystal"].apex}."
  description = "DNS zone for the trycrystal.org interactive tutorial"
  project     = var.project_id

  dnssec_config {
    state = "on"
  }
}
