# The five public applications, one per app_config entry.
#
# Ingress is INTERNAL_AND_CLOUD_LOAD_BALANCING, so the only route in is the
# global external load balancer in the edge module. The run.app URL is not a
# second front door, which keeps the sites off search engines under a second
# hostname and means nothing can bypass whatever the edge grows later.
# allUsers holds run.invoker so the load balancer is not rejected at the IAM
# layer; ingress, not IAM, is what does the restricting here.
#
# Scale to zero with startup CPU boost. These sites have had no traffic for
# years, so paying for an idle instance is paying for nothing, and the boost is
# what keeps the resulting cold start tolerable.
#
# There is a startup probe and deliberately no liveness probe. /api/health
# returns 503 when the database check fails, which is the behaviour you want at
# startup, because a revision with a broken DATABASE_URL or a missing Cloud SQL
# socket then refuses to be promoted instead of serving errors under a green
# deploy. As a liveness probe the same endpoint would restart every instance
# during a database blip, converting a brief degradation into an outage. For
# trycrystal, which has no database, the same probe on the same path is what
# proves the web app booted at all; the runner it calls is probed separately on
# its own service.
resource "google_cloud_run_v2_service" "apps" {
  for_each = local.app_config

  project  = var.project_id
  name     = each.key
  location = var.region
  ingress  = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account                  = google_service_account.apps[each.key].email
    timeout                          = "${var.request_timeout_seconds}s"
    max_instance_request_concurrency = var.request_concurrency

    scaling {
      min_instance_count = 0
      max_instance_count = each.value.max_instances
    }

    # The Cloud SQL socket, only for the apps whose app_config entry says they
    # have a database. trycrystal is the exception and the reason this is
    # conditional: mounting a database socket into a service designed to hold
    # no database wires a capability nothing in the app uses, and the volume is
    # how the connection name travels.
    dynamic "volumes" {
      for_each = each.value.database ? [1] : []
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloud_sql_connection_name]
        }
      }
    }

    containers {
      image = local.app_images[each.key]

      ports {
        name           = "http1"
        container_port = var.container_port
      }

      resources {
        limits = {
          cpu    = each.value.cpu
          memory = each.value.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      dynamic "volume_mounts" {
        for_each = each.value.database ? [1] : []
        content {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }
      }

      dynamic "env" {
        for_each = each.value.env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = each.value.secret_env
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
    app         = each.key
    environment = "production"
    managed_by  = "terraform"
  }

  lifecycle {
    ignore_changes = [
      # CI owns the tag after creation. See var.image_tag.
      template[0].containers[0].image,
      # gcloud stamps these on every `run services update` and terraform would
      # otherwise propose reverting them on the next plan, forever.
      client,
      client_version,
    ]
  }

  # A revision starts before terraform finishes the rest of the graph, so the
  # permissions it needs to read its own secrets and open its own database have
  # to exist first. Without these the first revision fails to start with a
  # Secret Manager permission error that looks like a broken image.
  depends_on = [
    google_secret_manager_secret_iam_member.secret_accessors,
    google_secret_manager_secret_version.secret_key_base,
    google_project_iam_member.cloudsql_client,
  ]
}
