# Network policy to allow crystaldocs namespace to access infrastructure namespace
resource "kubernetes_network_policy" "allow_infrastructure_access" {
  metadata {
    name      = "allow-infrastructure-access"
    namespace = kubernetes_namespace.crystaldocs.metadata[0].name
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
}
