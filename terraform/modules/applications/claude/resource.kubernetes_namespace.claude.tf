# Kubernetes namespace for claude agent
resource "kubernetes_namespace" "claude" {
  metadata {
    name = "claude"
    labels = {
      "app.kubernetes.io/name"    = "claude-agent"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
}
