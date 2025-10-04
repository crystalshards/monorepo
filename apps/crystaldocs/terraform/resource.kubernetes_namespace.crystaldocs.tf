# Kubernetes namespace for shards documentation
resource "kubernetes_namespace" "crystaldocs" {
  metadata {
    name = "crystaldocs"
    labels = {
      "app.kubernetes.io/name"    = "shards-docs"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
}
