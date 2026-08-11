locals {
  # Flatten { site key -> { apex, www, dns_zone } } into { hostname -> zone name }
  # so the record resource is one obvious record per hostname.
  a_records = merge([
    for site in var.sites : {
      (site.apex) = site.dns_zone
      (site.www)  = site.dns_zone
    }
  ]...)
}
