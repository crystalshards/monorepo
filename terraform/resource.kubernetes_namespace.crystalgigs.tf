# Kubernetes namespace for gigs board
resource "kubernetes_namespace" "crystalgigs" {
  metadata {
    name = "crystalgigs"
    labels = {
      "app.kubernetes.io/name"    = "gigs-board"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
  depends_on = [google_container_cluster.primary]
}
