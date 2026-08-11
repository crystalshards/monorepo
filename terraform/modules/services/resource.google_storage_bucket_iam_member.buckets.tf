# Object access, from the table in locals.tf.
#
# docs-build is not in that table and holds no bucket role of any kind. It
# reaches storage only through the signed GET and signed PUT that docs-launcher
# mints for it, which is the property that lets this project run untrusted
# shard code at all.
resource "google_storage_bucket_iam_member" "buckets" {
  for_each = local.bucket_grants

  bucket = each.value.bucket
  role   = each.value.role
  member = each.value.member
}
