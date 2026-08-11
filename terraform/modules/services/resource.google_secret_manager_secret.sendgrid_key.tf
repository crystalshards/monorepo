# CONTAINER ONLY. Terraform deliberately creates NO version for this secret.
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
# A revision referencing a secret with no versions will not start, so this fails
# loudly and closed rather than quietly and wrong. Do NOT add a placeholder
# version to make the first apply green. A committed placeholder is exactly the
# bug that terraform.tfvars had, where four secret variables were pinned to
# "unused" and silently outranked the real values CI passed, producing a green
# pipeline with mail and payments dead.
#
# One key per sending service rather than one shared key, so revoking a
# compromised key takes one site down instead of both.
#
# Only crystalgigs and crystalbits appear here. There is no opt out and no
# "off" value: a service that sends mail needs a real key and fails closed
# naming it, and a service that does not send mail has no secret at all.
resource "google_secret_manager_secret" "sendgrid_key" {
  for_each = local.mail_senders

  project   = var.project_id
  secret_id = "${each.key}-sendgrid-key"

  labels = {
    app        = each.key
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
