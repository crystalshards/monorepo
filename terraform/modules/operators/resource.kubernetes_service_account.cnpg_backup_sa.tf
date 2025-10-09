# Kubernetes ServiceAccount for CloudNativePG backups
resource "kubernetes_service_account" "cnpg_backup_sa" {
  metadata {
    name      = "cnpg-backup-sa"
    namespace = kubernetes_namespace.infrastructure.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = "cnpg-backup-sa@${var.cluster_name}.iam.gserviceaccount.com"
    }
  }
}
