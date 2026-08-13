# docs-launcher may start executions of the docs-build-core Job, and of
# nothing else beyond docs-build itself.
#
# Same role as docs_launcher_runs_docs_build and for the same reason:
# CrystalShards::CoreDocs starts this Job with per-build environment
# overrides (the four DOCS_* invocation variables plus the three signed
# URLs), which needs run.jobs.runWithOverrides. roles/run.invoker does not
# carry it, and every dispatch would fail on a permission that looks like it
# should already be granted.
#
# Bound on this Job specifically, not at project scope, for the same reason
# as the sibling binding: a project-scoped grant would let docs-launcher start
# the four migration Jobs too.
resource "google_cloud_run_v2_job_iam_member" "docs_launcher_runs_docs_build_core" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.docs_build_core.name
  role     = "roles/run.jobsExecutorWithOverrides"
  member   = "serviceAccount:${google_service_account.docs_launcher.email}"
}
