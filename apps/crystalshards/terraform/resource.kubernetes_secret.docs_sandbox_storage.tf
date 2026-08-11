# Object storage credentials for the documentation build Jobs.
#
# Kubernetes Secrets are namespace scoped, so the sandbox namespace cannot
# read `crystalshards-secrets`. Without this, the trusted fetch and upload
# steps of every build Job fail before they run.
#
# This is deliberately NOT a copy of the application secret. A build only
# needs to pull a source tarball and push a docs.json, so it gets object
# storage and nothing else. The application secret also carries
# SECRET_KEY_BASE and the database URL, and neither has any business in a
# namespace whose whole purpose is running other people's code.
resource "kubernetes_secret" "docs_sandbox_storage" {
  metadata {
    name      = "docs-sandbox-storage"
    namespace = kubernetes_namespace.docs_sandbox.metadata[0].name

    labels = {
      app       = "docs-sandbox"
      component = "storage-credentials"
    }
  }

  # Keys are lower case because the Job reads them with
  # secretKeyRef.key = <env name>.downcase.
  data = {
    minio_endpoint   = var.docs_sandbox_storage_endpoint
    minio_access_key = var.docs_sandbox_storage_access_key
    minio_secret_key = var.docs_sandbox_storage_secret_key
  }

  type = "Opaque"
}
