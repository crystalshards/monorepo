# A role containing exactly one permission: run.operations.get.
#
# Starting a Job with overrides does not return the execution. It returns a
# long-running operation, and the launcher has to poll that operation to learn
# whether the build finished, failed, or is still going. Reading it needs
# run.operations.get, which roles/run.jobsExecutorWithOverrides does not carry:
# that role is run.jobs.run, run.jobs.runWithOverrides and
# run.executions.cancel, all of which act on the Job and none of which read an
# operation.
#
# So the launcher could start builds and could not watch them. Every poll came
# back 403 and the loop retried until the deadline, which reads in the logs like
# a slow build rather than a missing grant.
#
# This cannot be bound on the Job. An operation is not a child of the Job it
# came from; it lives at projects/<p>/locations/<r>/operations/<id>, so the
# permission has to be granted at project scope or not at all. That is exactly
# why it is one permission rather than a predefined role: the smallest
# predefined role carrying it is roles/run.viewer, which at project scope would
# also let the launcher read every service, job, execution and revision in the
# project, including their environment. The launcher holds database and storage
# credentials; it should not also be able to enumerate everyone else's.
#
# Read only, and only of operations. It cannot start, cancel or alter anything
# through this role: the ability to run the docs-build Job comes from the
# separate Job-scoped binding, and that binding remains the only thing that
# names a Job.
#
# Creating this costs the deploy identity roles/iam.roleAdmin, which it already
# holds for the scheduler's runDiscoveryJob role.
resource "google_project_iam_custom_role" "read_run_operations" {
  project = var.project_id
  role_id = "readRunOperations"
  title   = "Read Cloud Run long-running operations"

  description = "Poll the operation returned when starting a Cloud Run Job execution. Exactly run.operations.get: no read of services, jobs, executions or revisions"

  permissions = ["run.operations.get"]
}

# Bound at project scope because an operation is not addressable under the Job
# that produced it. The role's single permission is what keeps that from
# widening anything: the launcher can read operations and nothing else, and it
# still cannot start any Job but docs-build.
resource "google_project_iam_member" "docs_launcher_reads_operations" {
  project = var.project_id
  role    = google_project_iam_custom_role.read_run_operations.id
  member  = "serviceAccount:${google_service_account.docs_launcher.email}"
}
