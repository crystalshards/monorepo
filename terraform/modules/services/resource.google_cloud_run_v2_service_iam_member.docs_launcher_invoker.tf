# The only principal that may call docs-launcher.
#
# The launcher has ingress ALL because Cloud Tasks reaches it over its public
# run.app URL, so this single binding is the entire access control on it. There
# is no allUsers grant, and adding one would turn a dispatcher that starts
# billable build Jobs into an anonymous endpoint for starting billable build
# Jobs.
resource "google_cloud_run_v2_service_iam_member" "docs_launcher_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.docs_launcher.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.docs_tasks.email}"
}
