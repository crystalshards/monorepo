locals {
  # Flatten { site key -> { apex, www, dns_zone } } into { hostname -> zone name }
  # so the record resource is one obvious record per hostname.
  a_records = merge([
    for site in var.sites : {
      (site.apex) = site.dns_zone
      (site.www)  = site.dns_zone
    }
  ]...)

  # The four managed zones as one slug keyed collection. The zone resources stay
  # separate so their existing terraform state addresses survive, and converting
  # them to a for_each collection would plan a destroy and recreate of zones that
  # are already delegated at the registrar. This local is the derived view, so
  # the outputs do not restate the four zones a second time.
  zones_by_site = {
    crystalshards = google_dns_managed_zone.crystalshards_org
    crystaldocs   = google_dns_managed_zone.crystaldocs_org
    crystalgigs   = google_dns_managed_zone.crystalgigs_com
    crystalbits   = google_dns_managed_zone.crystalbits_org
  }
}
