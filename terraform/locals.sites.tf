# The five public sites, and the single place any of their hostnames is written.
#
# Everything downstream is derived from this map: the serverless NEG and backend
# service per app, the URL map host rules, the ten Google managed certificates,
# and the ten DNS A records. Nothing else in the repo writes a hostname as a
# literal.
#
# That constraint exists because of a specific bug. When the certificate list,
# the URL map and the DNS records each carry their own copy of the hostnames,
# one copy eventually misses a name, and the result is a single domain silently
# serving a 404 or an untrusted certificate while the other three work. Deriving
# all three from one map makes that failure impossible: a name is present in all
# of them or in none of them.
#
# The map key is also the Cloud Run service key in module.services.service_names,
# so adding a site here without a matching service fails at plan rather than
# producing a load balancer pointed at nothing.
locals {
  site_domains = {
    crystalshards = "crystalshards.org"
    crystaldocs   = "crystaldocs.org"
    crystalgigs   = "crystalgigs.com"
    crystalbits   = "crystalbits.org"
    trycrystal    = "trycrystal.org"
  }

  # Cloud DNS managed zone name per site. The zone resources themselves live in
  # modules/dns and keep their existing terraform state addresses, because their
  # nameservers are already delegated at the registrar. Recreating them would
  # mean re-delegating four domains by hand.
  #
  # trycrystal-org is the exception: it is brand new, has no state to preserve
  # and no registrar delegation yet. The nameservers it issues have to be
  # delegated by hand before anything resolves; see
  # apps/trycrystal/REGISTRATION.md for the ordering, including why the DNSSEC
  # DS record is deliberately published only after delegation is confirmed.
  site_dns_zones = {
    crystalshards = "crystalshards-org"
    crystaldocs   = "crystaldocs-org"
    crystalgigs   = "crystalgigs-com"
    crystalbits   = "crystalbits-org"
    trycrystal    = "trycrystal-org"
  }

  # Apex plus www for every site, derived once. This is the only "www." in the
  # configuration. Both module.edge and module.dns receive this same value, so
  # they cannot be given different ideas of which hostnames exist.
  #
  # Iterating local.public_apps rather than local.site_domains keeps one
  # canonical app list for the whole stack: an app added there without a domain
  # and a zone here fails at plan with a missing key, rather than quietly
  # getting a Cloud Run service that nothing routes to. public_apps, not
  # database_apps, is the list of apps with a site: trycrystal is public and
  # holds no database.
  sites = {
    for slug in local.public_apps : slug => {
      apex     = local.site_domains[slug]
      www      = "www.${local.site_domains[slug]}"
      dns_zone = local.site_dns_zones[slug]
    }
  }
}
