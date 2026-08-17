# Warms documentation for the head of the popularity ranking.
#
# Shares the scheduler identity with the discovery sweep rather than minting a
# second one. Both do the same thing to the same kind of resource: POST :run to
# a Cloud Run Job in this project. The custom run_job role is already scoped to
# exactly that verb, and the binding is per job, so this identity can start
# these two jobs and nothing else. A second service account would carry the
# same permission under a different name.
#
# retry_count is 0 for the same reason discovery's is. A run that fails has
# already enqueued whatever it enqueued, and those builds are on the queue and
# unaffected; the next tick re-scans with fresher information. Retrying would
# re-walk the same ranking and skip everything the failed attempt commissioned.
resource "google_cloud_scheduler_job" "warm_popular_docs" {
  project = var.project_id
  region  = var.region
  name    = "warm-popular-docs"

  schedule    = var.warming_schedule
  description = "Commissions documentation builds for the most depended-upon shards, so the first reader of a popular shard is not the one who waits for its build"

  time_zone        = var.time_zone
  attempt_deadline = var.attempt_deadline

  retry_config {
    retry_count = 0
  }

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.warming_job_location}/jobs/${var.warming_job_name}:run"

    body = base64encode("{}")

    headers = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.discovery_scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.warming_scheduler]
}
