# The documentation build queue. crystalshards enqueues here, docs-launcher
# receives the dispatch and starts a docs-build Job execution.
#
# max_concurrent_dispatches is the load bearing setting in this file and it is
# small on purpose. Documentation is generated lazily, on first request for a
# package version, and the population of package times version is large. A
# crawler that walks it, which is the normal behaviour of every search engine
# rather than an attack, enqueues a build for every URL it touches. Without a
# concurrency cap that is a self inflicted denial of service where the bill and
# the outage arrive together, and the trigger is Googlebot doing its job. The
# cap converts an unbounded fan out into a queue that drains slowly, which for
# regenerable artifacts nobody is waiting on synchronously is the right shape.
#
# It is also only half of the ceiling. docs-launcher's max_instances is set to
# the same number in the services module, so the queue cannot outrun the thing
# it dispatches to even if this value is raised without thinking.
#
# retry_config bounds the other direction. A shard that fails to build will
# fail again, because the input is a fixed published version and the compiler
# is deterministic. Retrying it forever holds a build slot hostage to a
# permanent failure, so attempts are capped and the whole task expires.
#
# The cap that actually binds is max_retry_duration, and max_attempts is not a
# ceiling on this queue. That is the one thing to know before tuning anything
# in this block. Measured live over seven days: 35,918 dispatch attempts
# against 5,379 tasks created, 6.68 attempts per task, with max_attempts
# already set to 3, and individual tasks sitting at dispatchCount 7 to 11.
# Cloud Tasks does not charge a 429 or a 503 against the attempt budget, and a
# docs-launcher that is already holding all max_concurrent_dispatches of its
# slots answers exactly those, so on a queue whose failure mode is saturation
# the attempt counter is the one bound that never fires. Lowering max_attempts
# looks like the cheap fix and buys nothing; the wall clock is the only thing
# the API will enforce here. See var.max_retry_duration for how 900s is sized.
#
# min_backoff is 60s and it is doing as much work as the retry ceiling. Every
# dispatch wakes a docs-launcher instance and holds it for the whole build, so
# the floor on the backoff is the floor on how often a permanently failing task
# can bill for an instance. It was 30s, which is where the retry half of this
# pipeline's bill came from; doubling it halves that rate.
#
# max_burst_size is deliberately not set. Cloud Tasks derives it from
# max_dispatches_per_second, and pinning it here would add a value to argue
# with the API about for no behavioural gain.
resource "google_cloud_tasks_queue" "docs_builds" {
  project  = var.project_id
  name     = "docs-builds"
  location = var.region

  rate_limits {
    max_concurrent_dispatches = var.max_concurrent_dispatches
    max_dispatches_per_second = var.max_dispatches_per_second
  }

  retry_config {
    max_attempts       = var.max_attempts
    max_retry_duration = var.max_retry_duration
    min_backoff        = "60s"
    max_backoff        = "600s"
    max_doublings      = 3
  }

  stackdriver_logging_config {
    # Full sampling. The volume is low by construction and a dropped log line
    # on a queue this size is the difference between diagnosing a stuck build
    # and guessing at it.
    sampling_ratio = 1.0
  }
}
