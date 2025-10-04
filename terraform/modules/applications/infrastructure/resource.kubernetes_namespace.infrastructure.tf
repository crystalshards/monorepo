# Kubernetes namespace for infrastructure components
resource "kubernetes_namespace" "infrastructure" {
  metadata {
    name = "infrastructure"
    labels = {
      "app.kubernetes.io/name"    = "infrastructure"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
}
