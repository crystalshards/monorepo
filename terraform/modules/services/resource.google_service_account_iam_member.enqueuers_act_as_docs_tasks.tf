# Permission to create a Cloud Task that carries an OIDC token for the
# docs-tasks identity.
#
# Cloud Tasks treats "mint a token as this service account" as impersonation,
# so an enqueuer needs serviceAccountUser on the identity the task will act as.
# It is bound on docs-tasks specifically rather than at project scope, so these
# two services can impersonate exactly one identity, and that identity can do
# exactly one thing: invoke docs-launcher.
resource "google_service_account_iam_member" "enqueuers_act_as_docs_tasks" {
  for_each = local.enqueuers

  service_account_id = google_service_account.docs_tasks.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${each.value}"
}
