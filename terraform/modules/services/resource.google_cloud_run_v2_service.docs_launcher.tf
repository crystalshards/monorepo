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
# the request genuinely lasts as long as the execution does. cpu_idle is false
# for the same reason: the launcher is waiting on a Job between requests and a
# throttled instance would stop polling it.
resource "google_cloud_run_v2_service" "docs_launcher" {
  project  = var.project_id
  name     = "docs-launcher"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account                  = google_service_account.docs_launcher.email
    timeout                          = "${var.docs_build_timeout_seconds}s"
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
        cpu_idle          = false
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
        initial_delay_seconds = 5
        period_seconds        = 5
        timeout_seconds       = 3
        failure_threshold     = 12

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
    google_secret_manager_secret_version.sendgrid_key,
    google_project_iam_member.cloudsql_client,
  ]
}
