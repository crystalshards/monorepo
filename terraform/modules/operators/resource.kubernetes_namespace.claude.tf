# Claude Namespace
# Namespace for the CrystalShards agent
resource "kubernetes_namespace" "claude" {
  metadata {
    name = "claude"
    labels = {
      "name"                         = "claude"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}
