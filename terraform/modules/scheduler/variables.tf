variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region the Cloud Scheduler job lives in. It does not have to match the Cloud Run job's region, but keeping them equal means one region name in the stack rather than two"
  type        = string
}

variable "discovery_job_name" {
  description = <<-DESC
    Name of the Cloud Run Job this schedule executes, taken from the services
    module rather than restated. The Cloud Run Jobs :run URI is built from it, and
    a name written twice is a schedule that can end up pointed at a job that does
    not exist, which Cloud Scheduler reports as a 404 in its own logs and nowhere
    a reader of the registry would look.
  DESC
  type        = string
}

variable "discovery_job_location" {
  description = "Region the Cloud Run Job runs in. Part of the :run URI and of the IAM binding's resource path, so it has to be the Job's region and not the scheduler's"
  type        = string
}

variable "discovery_schedule" {
  description = <<-DESC
    How often a bounded slice of the sweep runs, in unix-cron.

    Every six hours at 17 minutes past, so 00:17, 06:17, 12:17 and 18:17 UTC.

    Frequent small slices rather than rare large ones, because the crawler
    persists its cursor after every page: the cadence decides how fast the
    frontier advances, not whether a pass ever completes. Four runs a day means a
    host that stopped on a rate limit is retried within hours rather than days,
    and a full pass over a frontier the size of the one a live crawl found (817
    shards) completes inside a day.

    Not more often than that, for two reasons. The bottleneck is the host's rate
    limit and not the schedule, so an hourly cadence buys no additional coverage
    and just spends more of the budget being throttled. And executions of a Cloud
    Run Job are not mutually exclusive: a cadence shorter than the Job's timeout
    could start a second sweep while the first is still walking the same cursor,
    and the two would fight over it.

    The 17 minute offset is deliberate. On the hour is when every other scheduled
    thing in the world calls these same APIs, and the shared secondary rate limits
    on search endpoints are the ones that notice.
  DESC
  type        = string
  default     = "17 */6 * * *"
}

variable "time_zone" {
  description = "Time zone the schedule is interpreted in. UTC, because every rate limit window these hosts publish is measured in UTC and a schedule that shifts twice a year would drift against them"
  type        = string
  default     = "Etc/UTC"
}

variable "attempt_deadline" {
  description = <<-DESC
    How long Cloud Scheduler waits for the :run call itself.

    This is not the sweep's deadline and must not be sized as though it were. The
    Cloud Run Jobs :run endpoint creates an execution and returns an Operation
    immediately, so the call it is bounding takes a moment; the sweep's own
    ceiling is the Job's task timeout. 320s is generous for an API call and short
    enough that a genuinely wedged call is reported rather than held open.
  DESC
  type        = string
  default     = "320s"
}
