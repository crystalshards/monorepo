# Object storage credentials for the documentation build Jobs.
#
# Kubernetes Secrets are namespace scoped, so the sandbox namespace cannot
# read `crystalshards-secrets`. Without this, the trusted fetch and upload
# steps of every build Job fail before they run.
#
# Derived from the same MinIO data source the application secret uses, so
# there is one source of truth for these credentials rather than a second set
# threaded through variables.
#
# This is deliberately NOT a copy of the application secret. A build pulls a
# source tarball and pushes a docs.json, so it gets object storage and nothing
# else. The application secret also carries SECRET_KEY_BASE and the database
# URL, and neither has any business in a namespace whose entire purpose is
# running other people's code.
resource "kubernetes_secret" "docs_sandbox_storage" {
  metadata {
    name      = var.docs_sandbox_secret_name
    namespace = kubernetes_namespace.docs_sandbox.metadata[0].name

    labels = {
      app       = "docs-sandbox"
      component = "storage-credentials"
    }
  }

  # Keys are lower case because the Job reads them with
  # secretKeyRef.key = <env name>.downcase.
  data = {
    minio_endpoint   = "shared-storage-hl.infrastructure.svc.cluster.local:9000"
    minio_access_key = data.kubernetes_secret.minio_user.data["CONSOLE_ACCESS_KEY"]
    minio_secret_key = data.kubernetes_secret.minio_user.data["CONSOLE_SECRET_KEY"]
  }

  type = "Opaque"

  lifecycle {
    replace_triggered_by = [data.kubernetes_secret.minio_user.id]
  }
}
