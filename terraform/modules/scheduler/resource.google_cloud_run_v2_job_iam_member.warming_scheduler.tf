resource "google_cloud_run_v2_job_iam_member" "warming_scheduler" {
  project  = var.project_id
  location = var.warming_job_location
  name     = var.warming_job_name
  role     = google_project_iam_custom_role.run_job.id
  member   = "serviceAccount:${google_service_account.discovery_scheduler.email}"
}
