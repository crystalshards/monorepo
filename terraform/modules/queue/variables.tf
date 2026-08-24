variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "Region the queue lives in. Cloud Tasks queue location and the Cloud Run service it dispatches to should match"
  type        = string
}

variable "max_concurrent_dispatches" {
  description = <<-DESC
    The global documentation build concurrency cap. This is the single number
    that decides how much money an unauthenticated visitor can spend. See the
    comment on the queue resource for why it is small.
  DESC
  type        = number
  default     = 5
}

variable "max_dispatches_per_second" {
  description = "Sustained dispatch rate. A documentation build takes far longer than a second, so this is about smoothing a crawl burst, not throughput"
  type        = number
  default     = 1
}

variable "max_attempts" {
  description = <<-DESC
    Total attempts per task, first try included. A shard whose docs cannot build
    will never build, so retrying it forever burns a build slot on a guaranteed
    failure.

    Do not treat this as the retry bound, because Cloud Tasks does not enforce
    it as one. A 429 or a 503 is not charged against the attempt budget, and
    that is precisely what a docs-launcher at its concurrency ceiling returns,
    so live tasks were observed at dispatchCount 7 to 11 with this set to 3.
    Anyone reaching for this number to bound cost wants max_retry_duration.
  DESC
  type        = number
  default     = 3
}

variable "max_retry_duration" {
  description = <<-DESC
    Hard stop on retries, measured from the first attempt, and the only retry
    bound Cloud Tasks reliably enforces on this queue. max_attempts reads like
    the control and is not one: a 429 or a 503 from a saturated docs-launcher is
    not charged against the attempt budget, so tasks measured on the live queue
    carried 7 to 11 dispatches while max_attempts was 3. The previous 7200s was
    sized against three full length attempts, which means it was sized against
    a limit that was never reached, and the result was 6.68 dispatches per task
    created over a measured week.

    900s is sized against the cost instead. The failures that generated that
    volume return in seconds rather than minutes, and with min_backoff at 60s,
    max_backoff at 600s and max_doublings at 3 the retries land roughly 60s,
    180s and 420s after the first attempt, with the next one falling at or past
    the 900s wall: four attempts inside a quarter hour, then the task is gone.

    The tradeoff is at the slow end and it is deliberate. A build that consumes
    its full docs_build_timeout_seconds of 1800s and then fails gets no retry at
    all, because the window closed while the first attempt was still running.
    That is the correct direction for this workload: documentation is
    regenerable and nobody waits on it synchronously, so the next request for
    the page re-enqueues it, while a build expensive enough to burn half an hour
    does not get to burn it three times in a row.
  DESC
  type        = string
  default     = "900s"
}
