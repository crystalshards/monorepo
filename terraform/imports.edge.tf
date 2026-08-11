# Adopt the four apex A records that already exist in Cloud DNS.
#
# Each zone holds one apex A record pointing at 136.114.166.228, created years
# ago by external-dns and never present in terraform state. Terraform cannot
# create a record set that already exists, so without these imports the first
# apply fails with an already-exists error on all four zones. With them, the
# records are adopted and updated in place to the load balancer address, and the
# dead value is gone.
#
# Only the apexes are adopted. No zone has a www record, so those four are
# ordinary creates.
#
# These blocks are safe to leave in place. An import block whose target is
# already in state is a no-op, so subsequent plans are unaffected, and the block
# is a record of where the record set came from.
#
# This lives outside imports.tf on purpose: that file imports cluster, VPC and
# Kubernetes resources that are being deleted wholesale along with the file.
import {
  for_each = local.sites

  to = module.dns.google_dns_record_set.a[each.value.apex]
  id = "projects/${var.project_id}/managedZones/${each.value.dns_zone}/rrsets/${each.value.apex}./A"
}
