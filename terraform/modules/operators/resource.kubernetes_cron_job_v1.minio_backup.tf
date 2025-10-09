# MinIO backup CronJob
resource "kubernetes_cron_job_v1" "minio_backup" {
  metadata {
    name      = "minio-backup"
    namespace = kubernetes_namespace.infrastructure.metadata[0].name
    labels = {
      app     = "minio-backup"
      purpose = "backup"
    }
  }

  spec {
    schedule                      = "0 4 * * *" # 4 AM daily
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 1

    job_template {
      metadata {
        labels = {
          app     = "minio-backup"
          purpose = "backup"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app     = "minio-backup"
              purpose = "backup"
            }
            annotations = {
              "iam.gke.io/gcp-service-account" = "minio-backup-sa@${var.cluster_name}.iam.gserviceaccount.com"
            }
          }

          spec {
            service_account_name = "minio-backup-sa"
            restart_policy       = "OnFailure"

            container {
              name  = "minio-backup"
              image = "minio/mc:latest"

              command = ["/bin/sh", "-c"]
              args = [
                <<-EOT
                set -e
                echo "Starting MinIO backup at $(date)"

                # Install gsutil for GCS access
                apk add --no-cache python3 py3-pip curl
                pip3 install --break-system-packages gsutil

                # Configure MinIO source
                mc alias set source http://shared-storage-hl:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD

                # Create timestamp
                TIMESTAMP=$(date +%Y%m%d-%H%M%S)

                # Backup packages bucket
                echo "Backing up packages bucket..."
                mc mirror source/packages /tmp/packages
                gsutil -m rsync -r /tmp/packages gs://${var.minio_backup_bucket}/minio/packages-$TIMESTAMP/

                # Backup docs bucket
                echo "Backing up docs bucket..."
                mc mirror source/docs /tmp/docs
                gsutil -m rsync -r /tmp/docs gs://${var.minio_backup_bucket}/minio/docs-$TIMESTAMP/

                # Also keep a 'latest' copy for easy restore
                gsutil -m rsync -r /tmp/packages gs://${var.minio_backup_bucket}/minio/latest/packages/
                gsutil -m rsync -r /tmp/docs gs://${var.minio_backup_bucket}/minio/latest/docs/

                echo "MinIO backup completed successfully at $(date)"
                EOT
              ]

              env {
                name = "MINIO_ROOT_USER"
                value_from {
                  secret_key_ref {
                    name = "shared-storage-env-configuration"
                    key  = "config.env"
                  }
                }
              }

              env {
                name = "MINIO_ROOT_PASSWORD"
                value_from {
                  secret_key_ref {
                    name = "shared-storage-env-configuration"
                    key  = "config.env"
                  }
                }
              }

              resources {
                requests = {
                  cpu    = "250m"
                  memory = "512Mi"
                }
                limits = {
                  cpu    = "1000m"
                  memory = "2Gi"
                }
              }

              volume_mount {
                name       = "backup"
                mount_path = "/tmp"
              }
            }

            volume {
              name = "backup"
              empty_dir {
                size_limit = "50Gi"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubectl_manifest.shared_minio,
    kubernetes_service_account.minio_backup_sa
  ]
}
