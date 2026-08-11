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
# Publishable rather than secret, but held here alongside its pair so Stripe has
# one rotation path rather than two.
resource "google_secret_manager_secret" "stripe_publishable_key" {
  project   = var.project_id
  secret_id = "crystalgigs-stripe-publishable-key"

  labels = {
    app        = "crystalgigs"
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
