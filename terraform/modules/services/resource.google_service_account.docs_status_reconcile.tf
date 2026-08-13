# The identity that reconciles documentation build state against published
# artifacts. It needs the registry and documentation databases plus read access
# to the documentation bucket. It cannot write objects, enqueue builds, or read
# any application secret other than those two database connection strings.
resource "google_service_account" "docs_status_reconcile" {
  project      = var.project_id
  account_id   = "docs-status-reconcile"
  display_name = "Documentation status reconciliation identity"
}
