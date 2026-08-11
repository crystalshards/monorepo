# docs-launcher. The only trusted component in the documentation build path.
#
# It receives a Cloud Tasks dispatch, mints a signed GET for the package source
# and a signed PUT for the built output, starts a docs-build execution with
# those two URLs as overrides, and records the outcome. Everything it can do is
# enumerated in the four IAM files that name it, and the list is short on
# purpose: it is the identity that stands between untrusted shard code and this
# project's storage.
resource "google_service_account" "docs_launcher" {
  project      = var.project_id
  account_id   = "docs-launcher"
  display_name = "Documentation build dispatcher"
}
