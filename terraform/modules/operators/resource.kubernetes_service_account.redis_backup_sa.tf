# Kubernetes ServiceAccount for Redis backups
resource "kubernetes_service_account" "redis_backup_sa" {
  metadata {
    name      = "redis-backup-sa"
    namespace = kubernetes_namespace.infrastructure.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = "redis-backup-sa@${var.cluster_name}.iam.gserviceaccount.com"
    }
  }
}
