# Data source to fetch CNPG-generated database credentials
# CNPG creates a secret named <cluster-name>-app with username and password
data "kubernetes_secret" "crystalshards_postgres_app" {
  metadata {
    name      = "crystalshards-postgres-app"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
  }

  # This secret is created by CNPG operator after the cluster is ready
  depends_on = [kubectl_manifest.crystalshards_postgres]
}
