# Redis backup CronJob
resource "kubernetes_cron_job_v1" "redis_backup" {
  metadata {
    name      = "redis-backup"
    namespace = kubernetes_namespace.infrastructure.metadata[0].name
    labels = {
      app     = "redis-backup"
      purpose = "backup"
    }
  }

  spec {
    schedule                      = "0 3 * * *" # 3 AM daily
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          app     = "redis-backup"
          purpose = "backup"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app     = "redis-backup"
              purpose = "backup"
            }
            annotations = {
              "iam.gke.io/gcp-service-account" = "redis-backup-sa@${var.cluster_name}.iam.gserviceaccount.com"
            }
          }

          spec {
            service_account_name = "redis-backup-sa"
            restart_policy       = "OnFailure"

            container {
              name  = "redis-backup"
              image = "redis:7-alpine"

              command = ["/bin/sh", "-c"]
              args = [
                <<-EOT
                set -e
                echo "Starting Redis backup at $(date)"

                # Trigger BGSAVE
                redis-cli -h shared-redis BGSAVE
                echo "BGSAVE triggered, waiting 10 seconds..."
                sleep 10

                # Wait for BGSAVE to complete
                while [ "$(redis-cli -h shared-redis LASTSAVE)" = "$LASTSAVE" ]; do
                  echo "Waiting for BGSAVE to complete..."
                  sleep 5
                done

                # Install gsutil
                apk add --no-cache python3 py3-pip curl
                pip3 install --break-system-packages gsutil

                # Download RDB file
                mkdir -p /backup
                redis-cli -h shared-redis --rdb /backup/dump.rdb

                # Upload to GCS with timestamp
                TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                gsutil cp /backup/dump.rdb gs://${var.redis_backup_bucket}/redis/dump-$TIMESTAMP.rdb

                echo "Redis backup completed successfully at $(date)"
                EOT
              ]

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }

              volume_mount {
                name       = "backup"
                mount_path = "/backup"
              }
            }

            volume {
              name = "backup"
              empty_dir {}
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubectl_manifest.shared_redis,
    kubernetes_service_account.redis_backup_sa
  ]
}
