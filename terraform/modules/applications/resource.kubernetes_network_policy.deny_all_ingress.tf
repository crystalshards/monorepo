# Network policy to deny all ingress traffic by default
resource "kubernetes_network_policy" "deny_all_ingress" {
  for_each = toset(["claude", "crystalshards", "crystaldocs", "crystalgigs", "infrastructure"])

  metadata {
    name      = "deny-all-ingress"
    namespace = each.key
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }

  depends_on = [
    kubernetes_namespace.claude,
    kubernetes_namespace.crystalshards,
    kubernetes_namespace.crystaldocs,
    kubernetes_namespace.crystalgigs,
    kubernetes_namespace.infrastructure
  ]
}
