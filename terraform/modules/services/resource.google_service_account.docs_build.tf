# docs-build. The identity that runs untrusted third party code.
#
# THIS SERVICE ACCOUNT HOLDS NO IAM BINDINGS ANYWHERE, AND THAT IS THE DESIGN.
#
# `crystal docs` compiles the shard it is documenting, and Crystal macros can
# execute arbitrary commands at compile time. Every execution of this Job is
# therefore an arbitrary code execution by a stranger, in a container, with
# this identity attached and a metadata server one HTTP call away. Any role
# bound to it becomes a role that stranger holds.
#
# So it gets none. Its input arrives as a signed GET URL and its output leaves
# as a signed PUT URL, both minted by docs-launcher, both scoped to one object,
# both expiring. The Job needs no bucket role because the URLs already carry
# the authorisation, and it needs no database, no queue and no secret because
# it is handed everything it may touch.
#
# If you are here because a build is failing with a 403 and you are about to
# add roles/storage.objectAdmin: don't. The signed URL is either missing,
# expired, or scoped to a different object than the one being written, and the
# fix is in docs-launcher. Granting a role here is how the sandbox stops being
# a sandbox, and an identity with no permissions is the property that made this
# runtime the right choice for running strangers' code.
resource "google_service_account" "docs_build" {
  project      = var.project_id
  account_id   = "docs-build"
  display_name = "Untrusted documentation build identity, intentionally without permissions"
}
