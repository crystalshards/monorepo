# Kubernetes namespace for newsletter site
resource "kubernetes_namespace" "crystalbits" {
  metadata {
    name = "crystalbits"
    labels = {
      "app.kubernetes.io/name"    = "newsletter"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
}
