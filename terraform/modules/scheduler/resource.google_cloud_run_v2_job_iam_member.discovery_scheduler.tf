# The whole of the scheduler caller's authority: run.jobs.run, on the discovery
# Job, and nothing anywhere else.
#
# Bound on this Job rather than at project scope, so the timer cannot start the
# four migration Jobs or the untrusted docs-build sandbox. That distinction is the
# reason the binding is here and not a project IAM member: roles at project scope
# would make the schedule able to run every Job in the stack, and a scheduled
# migration is a schema change nobody asked for.
#
# There is deliberately no second binding for this principal. It cannot read the
# Job, cannot list executions, cannot cancel one, and holds no accessor binding on
# any secret. It starts one thing on a timer and that is all it is for.
resource "google_cloud_run_v2_job_iam_member" "discovery_scheduler" {
  project  = var.project_id
  location = var.discovery_job_location
  name     = var.discovery_job_name
  role     = google_project_iam_custom_role.run_job.id
  member   = "serviceAccount:${google_service_account.discovery_scheduler.email}"
}
