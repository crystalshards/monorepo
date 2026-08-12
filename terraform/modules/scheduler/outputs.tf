output "discovery_schedule_name" {
  description = "Name of the Cloud Scheduler job that starts the discovery sweep"
  value       = google_cloud_scheduler_job.discover_shards.name
}

output "discovery_schedule" {
  description = "The cadence the sweep runs on, in unix-cron, as applied"
  value       = google_cloud_scheduler_job.discover_shards.schedule
}

output "discovery_scheduler_service_account_email" {
  description = "The caller identity Cloud Scheduler presents to the Cloud Run Jobs API. Holds one binding: a custom role of exactly run.jobs.run, on the discovery Job only"
  value       = google_service_account.discovery_scheduler.email
}

output "discovery_scheduler_role_id" {
  description = "Fully qualified id of the custom role bound to the caller. Its permission list is exactly [run.jobs.run]"
  value       = google_project_iam_custom_role.run_job.id
}
