# Kubernetes ServiceAccount for MinIO backups
resource "kubernetes_service_account" "minio_backup_sa" {
  metadata {
    name      = "minio-backup-sa"
    namespace = kubernetes_namespace.infrastructure.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = "minio-backup-sa@${var.cluster_name}.iam.gserviceaccount.com"
    }
  }
}
