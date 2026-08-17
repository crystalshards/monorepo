# Documentation warming, executing `./warm-popular-docs` from the crystalshards
# image.
#
# Documentation is built on first request. That is right for a catalogue whose
# long tail is never opened and wrong for its head: the first reader of the
# most depended-upon shard in the ecosystem waits minutes for a clone and a
# compile. This warms the head on a schedule so the tail can stay lazy.
#
# It commissions nothing itself. Every build goes onto the same queue, through
# the same worker, as a build a reader asks for, so a warm build and a
# requested one are the same build with the same recorded outcome. That is why
# this Job needs the enqueuer environment and not a builder's: it never clones
# anything and never compiles anything.
#
# max_retries is 0. A run that dies partway has enqueued whatever it enqueued,
# and those builds are already on the queue and unaffected. Re-entering from the
# top would re-scan the same head of the ranking and skip everything it just
# commissioned, which is harmless and pointless. The next tick does the same
# work with fresher information.
#
# The bound on builds is small on purpose. The build fleet is shared with the
# requests readers are waiting on right now, and a warm run that filled the
# queue would make a reader's own page wait behind work nobody asked for.
# Throughput comes from the schedule, not from the batch size.
resource "google_cloud_run_v2_job" "warm_popular_docs" {
  project  = var.project_id
  name     = "warm-popular-docs"
  location = var.region

  template {
    parallelism = 1
    task_count  = 1

    template {
      service_account = google_service_account.warm_popular_docs.email
      max_retries     = 0

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloud_sql_connection_name]
        }
      }

      containers {
        image   = local.app_images["crystalshards"]
        command = ["./warm-popular-docs"]

        resources {
          limits = {
            cpu = "1"
            # One popularity query, one batched lookup against the docs
            # database and a handful of queue writes. It holds a list of
            # candidates, not a repository.
            memory = "512Mi"
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }

        dynamic "env" {
          for_each = local.warm_popular_docs_config.env
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = local.warm_popular_docs_config.secret_env
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
    component   = "docs-warming"
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
