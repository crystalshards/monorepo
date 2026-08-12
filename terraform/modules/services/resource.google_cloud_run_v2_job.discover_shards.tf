# The shard discovery sweep, executing `./discover-shards` from the crystalshards
# image.
#
# A Job and not an HTTP handler. A sweep walks every host's search API page by
# page, backing off on each host's own rate limit headers, and one live GitHub
# crawl during development found 817 shards. That does not fit inside a request:
# Cloud Run caps a request at 3600s, an in-request crawl would hold an instance
# and its connection pool for the duration, and the moment the request is
# abandoned the sweep dies wherever it happened to be. It is work with a
# deadline, so it gets a task.
#
# The binary is ./discover-shards, a purpose built entrypoint alongside ./migrate
# that requires only what a crawl needs. It is not the Lucky task runner, which
# loads src/app and therefore all of config/**, and would drag the entire serving
# configuration surface into a crawl: PORT, SECRET_KEY_BASE, the bucket names,
# JOB_ADS_URL, the mail and payment configuration, none of which describe
# discovering a repository. See the comment on local.migration_config for the
# treadmill that produced.
#
# max_retries is 0, and that is a correctness requirement rather than thrift. The
# crawler persists its cursor after every page, so an interrupted sweep resumes
# from where it stopped. A retry re-enters the sweep from the top: it re-reads the
# cursor, so it does not lose the frontier, but it does spend a second slice of
# the host's rate limit inside the same window that the first attempt already
# exhausted, which is the one condition most likely to have killed it. A failed
# slice costs nothing. The next scheduled run continues from the same cursor.
#
# Note that being rate limited is not a failed execution at all. A throttled host
# comes back partial with its cursor saved and the run exits 0, so the next tick
# simply continues it; retries are not what makes throttling survivable, the
# cursor is. The exit codes the binary actually uses:
#
#   0  the sweep ran. Includes a host reported as skipped for want of a token, and
#      a host that stopped partway on a rate limit.
#   1  a configured host errored outright, which for bitbucket.org includes a
#      registered workspace answering 403. A real access problem, not throttling.
#   2  the Job's own environment is wrong, checked before any host is touched. Look
#      at this file and at var.discovery_max_pages, not at a git host. At the
#      6 hour cadence a 2 repeats until someone changes terraform, and the first
#      line of stderr names the offending variable.
#
# timeout is deliberately not the 600s default. See var.discovery_timeout_seconds.
resource "google_cloud_run_v2_job" "discover_shards" {
  project  = var.project_id
  name     = "discover-shards"
  location = var.region

  template {
    parallelism = 1
    task_count  = 1

    template {
      service_account = google_service_account.discover_shards.email
      timeout         = "${var.discovery_timeout_seconds}s"
      max_retries     = 0

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloud_sql_connection_name]
        }
      }

      containers {
        image   = local.app_images["crystalshards"]
        command = ["./discover-shards"]

        resources {
          limits = {
            cpu = "1"
            # A sweep holds one page of results and one repository at a time, and
            # writes each row as it goes. It is bound by other people's rate
            # limits, not by memory.
            memory = "512Mi"
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }

        dynamic "env" {
          for_each = local.discovery_config.env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = local.discovery_config.secret_env
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }
      }
    }
  }

  labels = {
    app         = "crystalshards"
    component   = "discovery"
    environment = "production"
    managed_by  = "terraform"
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_secret_manager_secret_iam_member.secret_accessors,
    google_project_iam_member.cloudsql_client,
  ]
}
