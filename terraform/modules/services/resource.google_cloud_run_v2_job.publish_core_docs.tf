# publish-core-docs. One trusted bootstrap operation: build and publish the
# Crystal standard library's own documentation under the bare `crystal` key.
#
# This is NOT the compile sandbox. The untrusted compile still runs in
# docs-build-core, with zero-IAM identity and signed URLs in and out. This Job
# is the trusted half only, the same role docs-launcher already serves for a
# shard build: it clones the pinned official Crystal repository, starts the
# sandboxed docs-build-core execution, waits for it, validates the returned
# artifact, writes it to the docs bucket and records the outcome in the
# crystaldocs database.
#
# It exists because the first successful core build cannot be left to chance.
# Once one real core artifact exists, crystaldocs' dependency commissioning
# stops asking for floor versions it would never select anyway, because
# core_already_satisfies? can see a successful build that already answers those
# links. But until that first artifact exists, nothing in production is
# entitled to assume a reader will happen to land on the one shard whose
# declared floor equals the pinned compiler version. A dispatchable Job in CI is
# the explicit bootstrap.
#
# Same image as the crystalshards service, and the purpose-built entrypoint is
# ./publish-core-docs. Like ./discover-shards and ./reconcile-docs-status it
# deliberately does NOT load the whole app, so it needs only the variables that
# entrypoint really reads: the two database URLs, the docs bucket, the Cloud
# Run sandbox settings and the build-core Job name.
#
# Service account: docs-launcher. That identity already holds exactly the roles
# this Job needs and no more: Cloud SQL client on the two databases, storage
# viewer/creator on the docs bucket, IAM SignBlob for signed URLs, and
# run.jobsExecutorWithOverrides on docs-build and docs-build-core. Reusing it is
# the design, not a shortcut: this Job is the same trusted half of the same
# build pipeline under a second entrypoint, not a new privilege boundary.
resource "google_cloud_run_v2_job" "publish_core_docs" {
  project  = var.project_id
  name     = "publish-core-docs"
  location = var.region

  template {
    parallelism = 1
    task_count  = 1

    template {
      service_account = google_service_account.docs_launcher.email
      timeout         = local.docs_build_timeout
      max_retries     = 0

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloud_sql_connection_name]
        }
      }

      containers {
        image   = local.app_images["crystalshards"]
        command = ["./publish-core-docs"]

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }

        dynamic "env" {
          for_each = merge(local.common_env, {
            DOCS_BUCKET                  = var.docs_bucket_name
            DOCS_SANDBOX                 = "cloudrun"
            DOCS_BUILD_CORE_JOB          = google_cloud_run_v2_job.docs_build_core.name
            DOCS_BUILD_JOB_REGION        = var.region
            DOCS_BUILD_DEADLINE_SECONDS  = tostring(local.docs_build_deadline_seconds)
            DOCS_SANDBOX_TIMEOUT_SECONDS = tostring(local.docs_sandbox_timeout_seconds)
          })
          content {
            name  = env.key
            value = env.value
          }
        }

        env {
          name = "DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = var.database_url_secret_ids["crystalshards"]
              version = "latest"
            }
          }
        }

        env {
          name = "DOCS_DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = var.database_url_secret_ids["crystaldocs"]
              version = "latest"
            }
          }
        }
      }
    }
  }

  labels = {
    app         = "crystalshards"
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
    google_secret_manager_secret_iam_member.docs_launcher_secrets,
    google_project_iam_member.cloudsql_client,
  ]
}
