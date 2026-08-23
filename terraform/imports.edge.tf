# Adopt the apex A records that already existed in Cloud DNS before terraform
# managed them.
#
# Four zones each hold one apex A record pointing at 136.114.166.228, created
# years ago by external-dns and never present in terraform state. Terraform
# cannot create a record set that already exists, so without these imports the
# first apply fails with an already-exists error on those four zones. With them,
# the records are adopted and updated in place to the load balancer address, and
# the dead value is gone.
#
# THIS SET IS HISTORICAL AND MUST NOT GROW WITH local.sites.
#
# It once iterated local.sites, which reads as "every site's apex" but actually
# means "every apex that predates terraform". Adding trycrystal to local.sites
# silently widened it to a brand new domain, and the deploy died on
#
#   Error: Cannot import non-existent remote object
#   module.dns.google_dns_record_set.a["trycrystal.org"]
#
# because adoption is only meaningful for something that already exists. A new
# site's records are ordinary creates. Any site added here in future would fail
# the same way, so the list is written out rather than derived: the four names
# are a fact about the past, not a property of being a site.
#
# Only apexes are adopted. No zone had a www record, so those are creates too.
#
# These blocks are safe to leave in place. An import block whose target is
# already in state is a no-op, so subsequent plans are unaffected, and the block
# is a record of where the record set came from.
#
# This lives outside imports.tf on purpose: that file imports cluster, VPC and
# Kubernetes resources that are being deleted wholesale along with the file.
locals {
  # Apex to managed zone, for apexes that existed in Cloud DNS before
  # terraform. Deliberately literal on both sides: deriving the zone from
  # local.site_dns_zones would re-introduce exactly the coupling that broke the
  # deploy, by making this set track the site list again.
  adopted_apex_a_records = {
    "crystalshards.org" = "crystalshards-org"
    "crystaldocs.org"   = "crystaldocs-org"
    "crystalgigs.com"   = "crystalgigs-com"
    "crystalbits.org"   = "crystalbits-org"
  }
}

import {
  for_each = local.adopted_apex_a_records

  to = module.dns.google_dns_record_set.a[each.key]
  id = "projects/${var.project_id}/managedZones/${each.value}/rrsets/${each.key}./A"
}
