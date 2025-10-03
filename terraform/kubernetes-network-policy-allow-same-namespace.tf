# Network policy to allow traffic within the same namespace
resource "kubernetes_network_policy" "allow_same_namespace" {
  for_each = toset(["claude", "crystalshards", "crystaldocs", "crystalgigs", "infrastructure"])

  metadata {
    name      = "allow-same-namespace"
    namespace = each.key
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = each.key
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.claude,
    kubernetes_namespace.crystalshards,
    kubernetes_namespace.crystaldocs,
    kubernetes_namespace.crystalgigs,
    kubernetes_namespace.infrastructure
  ]
}
