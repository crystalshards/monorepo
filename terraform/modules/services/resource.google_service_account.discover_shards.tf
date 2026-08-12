# The identity the shard discovery sweep runs as.
#
# Separate from the crystalshards service account for the same reason each
# migration Job has its own: the sweep needs one database and the host tokens,
# and reusing the app's identity would additionally hand a crawler the packages
# bucket, the documentation bucket, the docs-builds queue, the crystaldocs
# database and the ability to mint signed URLs. It writes rows; it has no
# business signing a download.
#
# It is also the only identity in this stack that holds a credential for a
# system outside Google Cloud, which is the other half of the argument for
# keeping it alone. A leaked signing capability and a leaked GitHub token are
# different incidents, and they should not share a principal.
resource "google_service_account" "discover_shards" {
  project      = var.project_id
  account_id   = "discover-shards"
  display_name = "Shard discovery sweep identity"
}
