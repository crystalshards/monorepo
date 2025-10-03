# Kubernetes namespace for shards registry
resource "kubernetes_namespace" "crystalshards" {
  metadata {
    name = "crystalshards"
    labels = {
      "app.kubernetes.io/name"    = "shards-registry"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
  depends_on = [google_container_cluster.primary]
}
