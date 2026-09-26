# docs-launcher. Receives a Cloud Tasks dispatch, mints the two signed URLs,
# starts a docs-build execution, waits for it, records the outcome.
#
# Ingress is ALL, which reads like a mistake and is not. Cloud Tasks calls over
# the public run.app URL and is neither internal traffic nor load balancer
# traffic, so INTERNAL_AND_CLOUD_LOAD_BALANCING would block every dispatch.
# What makes this service private is IAM: allUsers holds nothing, and the only
# principal with run.invoker is the docs-tasks service account, so an
# unauthenticated request is a 403 before any handler runs. It is also not
# behind the load balancer and has no hostname of its own.
#
# max_instances is pinned to the queue's max_concurrent_dispatches. The launcher
# holds its request open for the whole build, so an instance is a build in
# flight, and this is the second half of the global concurrency cap: even if
# somebody raises the queue without thinking, the dispatcher cannot exceed what
# is declared here.
#
# The timeout is the build ceiling rather than the usual sixty seconds, because
# the request genuinely lasts as long as the execution does. cpu_idle is true
# (request-based billing): the launcher polls the Job strictly inside the
# synchronous HTTP request held open by Cloud Tasks, never between requests.
# Under cpu_idle = false, all 5 instances ran continuously 24/7, costing $182.38
# in 24 days ($172.97 CPU + $9.41 memory, or ~$228 per 30 days) and accounting
# for over half of the entire project bill. With cpu_idle = true, instances scale
# to zero when idle and are billed only while build requests are in flight.
resource "google_cloud_run_v2_service" "docs_launcher" {
  project = var.project_id
  # Shared with everything that names this service.
  name     = local.docs_launcher_service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # The audience Cloud Tasks mints build tokens for. Declared here so Cloud Run
  # accepts a token bearing it, and given to the launcher as an env var so it
  # can verify the same string. A literal rather than this service's own URL,
  # because a resource cannot consume its own output and the launcher has to be
  # told what to expect. Without it the caller check raised on every dispatch
  # and no documentation was ever built.
  custom_audiences = [local.docs_launcher_audience]


  template {
    service_account                  = google_service_account.docs_launcher.email
    timeout                          = local.docs_build_timeout
    max_instance_request_concurrency = 1

    scaling {
      min_instance_count = 0
      max_instance_count = var.docs_build_concurrency
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.cloud_sql_connection_name]
      }
    }

    containers {
      image = local.docs_launcher_image

      ports {
        name           = "http1"
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      dynamic "env" {
        for_each = local.docs_launcher_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.docs_launcher_secret_env
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

      startup_probe {
        initial_delay_seconds = 0
        period_seconds        = 1
        timeout_seconds       = 1
        failure_threshold     = 60

        http_get {
          path = var.health_path
          port = var.container_port
        }
      }
    }
  }

  labels = {
    app         = "docs-launcher"
    environment = "production"
    managed_by  = "terraform"
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_secret_manager_secret_iam_member.docs_launcher_secrets,
    google_secret_manager_secret_version.secret_key_base,
    google_project_iam_member.cloudsql_client,
  ]
}
