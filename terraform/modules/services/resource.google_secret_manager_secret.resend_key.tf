# CONTAINER ONLY. Terraform deliberately creates NO version for this secret.
#
# This holds the Resend API key each sending service authenticates its outbound
# mail with.
#
# This is a third party credential, so unlike the database passwords and the
# session keys it cannot be generated, and the only remaining question is which
# systems its value passes through on the way in. Handing it to terraform as a
# variable means it travels through CI, through a tf variable, and then sits in
# the state file in gs://crystalshards-org-terraform-state forever. Reading it
# back with a data source does not help: a data source lands the value in state
# too, so that swaps where the exposure lives rather than removing it.
#
# The value therefore never enters terraform at all. An operator populates it
# directly:
#
#   gcloud secrets versions add <secret-id> --data-file=-
#
# Do NOT add a placeholder version to make the first apply green. A committed
# placeholder is exactly the bug that terraform.tfvars had, where four secret
# variables were pinned to "unused" and silently outranked the real values CI
# passed, producing a green pipeline with mail and payments dead.
#
# One key per sending service rather than one shared key, so revoking a
# compromised key takes one site down instead of both.
#
# Only crystalgigs and crystalbits appear here. crystalshards, crystaldocs and
# docs-launcher send nothing and so have no secret at all, which is what lets
# them serve on a clean apply with no third party credential in existence.
#
# A revision that references a secret with no versions never reaches Ready, so
# the env var is attached separately and only once a version exists. See
# local.mail_enabled. Serving is the primary function and mail is a feature: the
# site stays up without a key and the adapter raises on an actual send attempt
# naming RESEND_API_KEY.
resource "google_secret_manager_secret" "resend_key" {
  # STATIC on purpose, both senders, always created, never keyed off the
  # populated list. Do not "tidy" this into local.mail_enabled.
  #
  # Destroying a Secret Manager secret destroys the versions inside it. If this
  # for_each tracked which keys CI currently has, then any deploy running while
  # a key is absent from the repository would propose destroying that container
  # and silently discard a version an operator added by hand with
  # `gcloud secrets versions add`. It would surface later as mail breaking on a
  # site that was working, with nothing in the diff that looks like a cause.
  #
  # Same principle as the rest of this file: terraform must not be able to
  # delete a value it was deliberately never allowed to see. Keeping the
  # container unconditional also means an operator has somewhere to put a key
  # the moment they have one, with no deploy required first.
  for_each = local.mail_senders

  project   = var.project_id
  secret_id = "${each.key}-resend-key"

  labels = {
    app        = each.key
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
