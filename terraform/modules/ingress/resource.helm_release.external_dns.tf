# External DNS for automatic DNS management
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.14.3"
  namespace  = "infrastructure"

  # Increase timeout for initial installation (GKE Autopilot can be slow)
  # Disable wait to avoid blocking deployment - external-dns can start async
  timeout = 900 # 15 minutes
  wait    = false

  set {
    name  = "provider"
    value = "google"
  }

  set {
    name  = "google.project"
    value = var.project_id
  }

  set {
    name  = "domainFilters[0]"
    value = "crystalshards.org"
  }

  set {
    name  = "domainFilters[1]"
    value = "crystaldocs.org"
  }

  set {
    name  = "domainFilters[2]"
    value = "crystalgigs.com"
  }

  set {
    name  = "domainFilters[3]"
    value = "crystalbits.org"
  }

  set {
    name  = "policy"
    value = "sync"
  }

  set {
    name  = "registry"
    value = "txt"
  }

  set {
    name  = "txtOwnerId"
    value = "crystalshards-k8s"
  }

  # Resource limits
  set {
    name  = "resources.requests.cpu"
    value = "25m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "50m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }
}
