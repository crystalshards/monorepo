# Schema migration Jobs, one per application, executing `./tasks db.migrate`
# from that application's own image.
#
# Migrations run here rather than from the CI runner. The runner would have to
# reach the database over its public IP from a GitHub owned address, which means
# either an authorized network covering a range nobody controls or a proxy
# credential on the runner. Both throw away the perimeter the rest of this stack
# is built on, to save creating four resources.
#
# max_retries is 0. A migration that failed halfway has already changed the
# schema, and the correct response is a human reading the error, not a second
# attempt against a database that is now in a state the migration did not
# expect.
resource "google_cloud_run_v2_job" "app_migrations" {
  for_each = local.migration_config

  project  = var.project_id
  name     = "${each.key}-migrate"
  location = var.region

  template {
    parallelism = 1
    task_count  = 1

    template {
      service_account = google_service_account.app_migrations[each.key].email
      timeout         = "900s"
      max_retries     = 0

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloud_sql_connection_name]
        }
      }

      containers {
        image   = local.app_images[each.key]
        command = ["./tasks"]
        args    = ["db.migrate"]

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
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
      }
    }
  }

  labels = {
    app         = each.key
    component   = "migrate"
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
