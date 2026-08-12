# The only thing in this stack that starts a shard discovery sweep.
#
# Before this existed the crawler was complete, tested and unreachable:
# DiscoverShardsWorker had no enqueuer, no scheduler existed anywhere in
# terraform, and the polling worker process was deleted in the Cloud Run
# migration. The registry's only paths to an indexed shard were POST /api/shards,
# POST /api/shards/upload and a GitHub webhook push, so a registry whose whole
# purpose is to find shards showed "No shards" and would have forever. This
# resource is the missing edge.
#
# Cloud Scheduler rather than a polling process, because Cloud Run has nothing
# that idles: a service scales to zero and a Job runs to completion, so "a thing
# that wakes up on an interval" has to be an external timer. It is the only
# scheduler in this stack, and nothing polls.
#
# The target is the Cloud Run Admin API's jobs.run method, not the Job's own
# ingress, because a Job has no URL to call. That is why the token below is an
# OAuth access token and not an OIDC identity token, and the distinction is not
# stylistic: run.googleapis.com is a Google API and authenticates Authorization:
# Bearer <access token> scoped to cloud-platform. An OIDC token is a Google signed
# ID token whose audience is the target URL, which is what a Cloud Run SERVICE
# validates at its ingress. Send one of those here and the API answers 401
# UNAUTHENTICATED, which surfaces as a schedule that fires on time and never
# starts anything. See the Terraform example in
# https://cloud.google.com/run/docs/execute/jobs-on-schedule, which uses
# oauth_token for exactly this URI.
resource "google_cloud_scheduler_job" "discover_shards" {
  project  = var.project_id
  region   = var.region
  name     = "discover-shards"
  schedule = var.discovery_schedule

  description = "Runs a bounded slice of the shard discovery sweep. The crawler resumes from its stored per host cursor, so each run continues the previous one rather than restarting it"

  time_zone        = var.time_zone
  attempt_deadline = var.attempt_deadline

  # No retries, and that is the safe direction here rather than the lazy one.
  #
  # A retry only helps if the :run call itself failed. If the call succeeded and
  # the response was merely lost, a retry starts a SECOND execution of a Job whose
  # first execution is still walking the same per host cursor, and the two write
  # over each other's progress while spending double the host's rate limit. Cloud
  # Run Jobs do not serialise executions for us.
  #
  # A missed tick, by contrast, costs nothing at all. The cursor is persisted
  # after every page, so the next scheduled run continues from exactly where the
  # skipped one would have started. Given a free failure mode and an expensive
  # one, this picks the free one.
  retry_config {
    retry_count = 0
  }

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.discovery_job_location}/jobs/${var.discovery_job_name}:run"

    # An empty RunJobRequest. Overrides would go here, and deliberately do not:
    # the caller's role does not carry run.jobs.runWithOverrides, so a body that
    # tried to change the container's environment would be rejected rather than
    # honoured. The Job's own definition is the only description of what runs.
    body = base64encode("{}")

    headers = {
      "Content-Type" = "application/json"
    }

    # oauth_token, NOT oidc_token. Do not "correct" this to match the OIDC used
    # elsewhere in the stack for docs-launcher: those are Cloud Run SERVICES with
    # an ingress that validates a Google signed ID token whose audience is the
    # service URL. A Job has no ingress, so the target above is the Cloud Run
    # Admin API, and a Google API authenticates with an OAuth access token.
    #
    # An OIDC token here answers 401 UNAUTHENTICATED, and the failure shape is
    # why this comment is long: the schedule still fires exactly on time, the
    # apply is clean, nothing is unhealthy, and the only evidence is a 401 in
    # Cloud Scheduler's own logs. Nobody reads those until someone asks why the
    # registry is still empty, and by then the plausible suspects are the token,
    # the crawler and the cursor.
    #
    # The scope grants nothing on its own. cloud-platform is the scope every
    # Google API access token carries; what the caller may actually do is the
    # custom role bound in
    # resource.google_cloud_run_v2_job_iam_member.discovery_scheduler.tf, whose
    # permission list is exactly ["run.jobs.run"] on this one Job.
    oauth_token {
      service_account_email = google_service_account.discovery_scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  # The binding, not just the identity. Cloud Scheduler validates neither at
  # create time, so without this edge the first apply can produce a schedule that
  # fires before its caller may start anything, and the only evidence is a 403 in
  # the scheduler's logs.
  depends_on = [google_cloud_run_v2_job_iam_member.discovery_scheduler]
}
