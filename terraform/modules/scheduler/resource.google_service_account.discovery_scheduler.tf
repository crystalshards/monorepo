# The identity Cloud Scheduler calls the Cloud Run Jobs API as.
#
# This is the CALLER, and it is not the discover-shards service account, which is
# the identity the sweep RUNS as. They are two different principals with two
# different jobs, and conflating them is the mistake this file exists to prevent:
# the caller needs to be able to start one Job and nothing else, while the runner
# needs a database and the host tokens and must never be able to start anything.
#
# It holds exactly one binding, in
# resource.google_cloud_run_v2_job_iam_member.discovery_scheduler.tf. No project
# scope grant, no key, and nothing on any other Job.
resource "google_service_account" "discovery_scheduler" {
  project      = var.project_id
  account_id   = "discovery-scheduler"
  display_name = "Cloud Scheduler caller for the shard discovery sweep"
}
