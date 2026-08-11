locals {
  # Every public hostname, apex and www, flattened out of var.sites. This single
  # set drives the managed certificates and is exported as public_hostnames, and
  # the same var.sites drives the URL map host rules here and the A records in
  # modules/dns. There is no second list to keep in step.
  hostnames = toset(flatten([
    for site in var.sites : [site.apex, site.www]
  ]))

  # Cloud Run service name per site, resolved eagerly so a site with no matching
  # service fails at plan with a clear missing-key error rather than at apply
  # with a NEG pointed at a service that does not exist.
  services = {
    for slug, site in var.sites : slug => var.service_names[slug]
  }
}
