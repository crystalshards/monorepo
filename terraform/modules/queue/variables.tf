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
  description = "Total attempts per task, first try included. A shard whose docs cannot build will never build, so retrying it forever burns a build slot on a guaranteed failure"
  type        = number
  default     = 3
}

variable "max_retry_duration" {
  description = <<-DESC
    Hard stop on retries, measured from the first attempt. Cloud Tasks stops at
    whichever of max_attempts and this comes first, so the two have to be sized
    against the work: a documentation build can run up to 1800s, and three
    attempts with the 600s maximum backoff between them is 3 x 1800 + 2 x 600 =
    6600s. At the obvious looking 3600s the third attempt would silently never
    happen, and max_attempts would be a number that does not mean what it says.
  DESC
  type        = string
  default     = "7200s"
}
