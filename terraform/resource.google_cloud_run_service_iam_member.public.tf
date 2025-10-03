# Make the Cloud Run service publicly accessible
resource "google_cloud_run_service_iam_member" "public" {
  location = google_cloud_run_service.simple_registry.location
  project  = google_cloud_run_service.simple_registry.project
  service  = google_cloud_run_service.simple_registry.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
