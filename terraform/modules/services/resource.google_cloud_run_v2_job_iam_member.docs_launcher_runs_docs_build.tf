# docs-launcher may start executions of the docs-build Job, and of nothing else.
#
# The role is roles/run.jobsExecutorWithOverrides rather than the more familiar
# roles/run.invoker, and the difference is not cosmetic. run.invoker carries
# run.instances.invoke, run.jobs.run and run.routes.invoke, and stops there. The
# launcher does not merely run this Job, it runs it with environment overrides,
# because the two signed URLs are per build values that cannot live in the Job
# definition. That needs run.jobs.runWithOverrides, which run.invoker does not
# have. Bound with run.invoker, every dispatch would fail with a permission
# error on an operation that looks like it should already be allowed.
#
# jobsExecutorWithOverrides is exactly three permissions: run.jobs.run,
# run.jobs.runWithOverrides and run.executions.cancel. The next role up that
# also carries overrides is roles/run.developer, which would additionally let
# the launcher rewrite what the Job runs, and the launcher must only be able to
# run it.
#
# Bound on this Job rather than at project scope, so the launcher cannot start
# the four migration Jobs.
resource "google_cloud_run_v2_job_iam_member" "docs_launcher_runs_docs_build" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.docs_build.name
  role     = "roles/run.jobsExecutorWithOverrides"
  member   = "serviceAccount:${google_service_account.docs_launcher.email}"
}
