# MinIO operator creates a secret for the tenant with credentials
# Secret name format: <tenant-name>-user-1
data "kubernetes_secret" "minio_user" {
  metadata {
    name      = "shared-storage-user-1"
    namespace = "infrastructure"
  }

  depends_on = [
    # Ensure MinIO tenant is created before trying to read its secret
    # This is handled by the applications module dependency
  ]
}
