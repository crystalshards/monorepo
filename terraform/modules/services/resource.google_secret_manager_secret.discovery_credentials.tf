# CONTAINER ONLY. Terraform deliberately creates NO version for any of these.
#
# These hold the per host API credentials the discovery sweep authenticates with:
# a token for github.com, gitlab.com and codeberg.org, and an account plus app
# password pair for bitbucket.org, which authenticates over HTTP Basic and so
# needs both halves.
#
# Same reasoning as the Resend key next door. These are third party credentials,
# so terraform cannot generate them, and the only remaining question is which
# systems the value passes through on the way in. Handing one to terraform as a
# variable means it travels through CI, through a tf variable, and then sits in
# the state file in gs://crystalshards-org-terraform-state forever. Reading it
# back with a data source lands it in state too, so that relocates the exposure
# rather than removing it.
#
# The value therefore never enters terraform. CI copies it from a repository
# secret, or an operator populates it directly:
#
#   gcloud secrets versions add <secret-id> --data-file=-
#
# Do NOT add a placeholder version to make the first apply green. A crawl started
# with a placeholder token does not fail loudly: GitHub answers code search with
# 401 and the rest of its API with a 60 per hour limit, so the sweep records a
# handful of repositories and a partial state, and the registry then looks like a
# host with almost no Crystal on it. Discovery::Credentials refuses to start a
# host without a real token precisely so that reads as configuration and not as
# an empty ecosystem.
resource "google_secret_manager_secret" "discovery_credentials" {
  # STATIC on purpose, all five, always created, never keyed off the populated
  # list. Do not "tidy" this into local.discovery_enabled_hosts.
  #
  # Destroying a Secret Manager secret destroys the versions inside it. If this
  # for_each tracked which credentials CI currently has, then any deploy running
  # while a token is absent from the repository would propose destroying that
  # container and silently discard a version an operator added by hand with
  # `gcloud secrets versions add`. It would surface later as a host that had been
  # crawling quietly stopping, with nothing in the diff that looks like a cause.
  #
  # Same principle as the rest of this file: terraform must not be able to delete
  # a value it was deliberately never allowed to see. Keeping the containers
  # unconditional also means an operator has somewhere to put a token the moment
  # they have one, with no deploy required first.
  for_each = local.discovery_credentials

  project   = var.project_id
  secret_id = each.value

  labels = {
    app        = "crystalshards"
    component  = "discovery"
    managed_by = "terraform"
  }

  replication {
    auto {}
  }
}
