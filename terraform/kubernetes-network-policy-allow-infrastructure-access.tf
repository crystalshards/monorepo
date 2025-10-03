# Network policy to allow application namespaces to access infrastructure namespace
resource "kubernetes_network_policy" "allow_infrastructure_access" {
  for_each = toset(["crystalshards", "crystaldocs", "crystalgigs"])

  metadata {
    name      = "allow-infrastructure-access"
    namespace = each.key
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "infrastructure"
          }
        }
      }
    }

    # Allow DNS resolution
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # Allow external HTTPS traffic
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }
  }

  depends_on = [
    kubernetes_namespace.crystalshards,
    kubernetes_namespace.crystaldocs,
    kubernetes_namespace.crystalgigs,
    kubernetes_namespace.infrastructure
  ]
}
