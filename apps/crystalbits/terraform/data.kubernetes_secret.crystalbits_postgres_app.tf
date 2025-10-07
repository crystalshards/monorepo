# Data source to fetch CNPG-generated database credentials
# CNPG creates a secret named <cluster-name>-app with username and password
data "kubernetes_secret" "crystalbits_postgres_app" {
  metadata {
    name      = "crystalbits-postgres-app"
    namespace = kubernetes_namespace.crystalbits.metadata[0].name
  }

  # This secret is created by CNPG operator after the cluster is ready
  depends_on = [kubectl_manifest.crystalbits_postgres]
}
