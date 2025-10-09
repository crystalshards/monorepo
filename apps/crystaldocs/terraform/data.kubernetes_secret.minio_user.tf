# MinIO operator generates credentials in the infrastructure namespace
# We access the user-1 credentials for CrystalDocs
data "kubernetes_secret" "minio_user" {
  metadata {
    name      = "shared-storage-user-1"
    namespace = "infrastructure"
  }

  # Depend on the MinIO cluster being created by the operators module
  depends_on = []
}
