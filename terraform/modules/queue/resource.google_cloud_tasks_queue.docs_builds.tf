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
    min_backoff        = "30s"
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
