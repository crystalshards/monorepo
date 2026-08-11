# Read access to individual secrets for the four applications and their
# migration Jobs, bound per secret rather than per project.
#
# The difference matters: roles/secretmanager.secretAccessor at project scope
# would let crystalbits read the Stripe key and let every migration Job read
# every database password. Bound here, each identity sees only the secrets its
# own revision references, which is the map in locals.tf.
#
# docs-build does not appear in that map and must never appear in it. It reads
# no secret, because everything it may touch arrives as a signed URL.
resource "google_secret_manager_secret_iam_member" "secret_accessors" {
  for_each = local.service_secret_accessors

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
