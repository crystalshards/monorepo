# Permission to open a connection to the Cloud SQL instance.
#
# roles/cloudsql.client cannot be bound to a single instance, so this project
# scope grant is the complete answer to "what can reach the database", and the
# local it iterates is the complete list. docs-build and docs-tasks are absent.
resource "google_project_iam_member" "cloudsql_client" {
  for_each = local.cloudsql_clients

  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${each.value}"
}
