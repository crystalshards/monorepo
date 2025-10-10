# Agent Service Account
# Service account for the CrystalShards agent running in the claude namespace
resource "kubernetes_service_account" "agent_sa" {
  metadata {
    name      = "crystalshards-agent"
    namespace = "claude"
    labels = {
      "app.kubernetes.io/name"       = "crystalshards-agent"
      "app.kubernetes.io/component"  = "agent"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  # Ensure namespace exists first
  depends_on = [kubernetes_namespace.claude]
}
