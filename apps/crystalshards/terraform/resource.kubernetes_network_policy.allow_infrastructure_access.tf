# Network policy to allow crystalshards namespace to access infrastructure namespace
resource "kubernetes_network_policy" "allow_infrastructure_access" {
  metadata {
    name      = "allow-infrastructure-access"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    # Allow Redis access in infrastructure namespace
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "infrastructure"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "6379"
      }
    }

    # Allow MinIO access in infrastructure namespace
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "infrastructure"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "9000"
      }
    }

    # Allow PostgreSQL access within same namespace
    # CRITICAL: Without this, app pods cannot connect to CNPG database
    egress {
      to {
        pod_selector {
          match_labels = {
            "cnpg.io/cluster" = "crystalshards-postgres"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "5432"
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
