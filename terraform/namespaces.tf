# Kubernetes namespaces for applications and infrastructure
resource "kubernetes_namespace" "claude" {
  metadata {
    name = "claude"
    labels = {
      "app.kubernetes.io/name"    = "claude-agent"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
  depends_on = [google_container_cluster.primary]
}

resource "kubernetes_namespace" "crystalshards" {
  metadata {
    name = "crystalshards"
    labels = {
      "app.kubernetes.io/name"    = "shards-registry"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
  depends_on = [google_container_cluster.primary]
}

resource "kubernetes_namespace" "crystaldocs" {
  metadata {
    name = "crystaldocs"
    labels = {
      "app.kubernetes.io/name"    = "shards-docs"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
  depends_on = [google_container_cluster.primary]
}

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

resource "kubernetes_namespace" "infrastructure" {
  metadata {
    name = "infrastructure"
    labels = {
      "app.kubernetes.io/name"    = "infrastructure"
      "app.kubernetes.io/part-of" = "crystalshards"
    }
  }
  depends_on = [google_container_cluster.primary]
}

# Network policies for namespace isolation
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
      to {}
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # Allow external HTTPS traffic
    egress {
      to {}
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