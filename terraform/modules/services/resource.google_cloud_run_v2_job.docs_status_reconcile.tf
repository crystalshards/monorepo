# Repairs historical doc_versions rows from the published docs.json artifacts.
#
# The binary is purpose built and idempotent. It lists the documentation bucket
# before reading or writing a row, updates only rows still marked pending, and
# treats an absent artifact as pending rather than as a failed build.
resource "google_cloud_run_v2_job" "docs_status_reconcile" {
  project  = var.project_id
  name     = "reconcile-docs-status"
  location = var.region

  template {
    parallelism = 1
    task_count  = 1

    template {
      service_account = google_service_account.docs_status_reconcile.email
      timeout         = "900s"
      max_retries     = 0

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloud_sql_connection_name]
        }
      }

      containers {
        image   = local.app_images["crystalshards"]
        command = ["./reconcile-docs-status"]

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
          for_each = local.docs_status_reconcile_config.env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = local.docs_status_reconcile_config.secret_env
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
    component   = "docs-status-reconcile"
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
    google_storage_bucket_iam_member.buckets,
  ]
}
