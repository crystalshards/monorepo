# External DNS for automatic DNS management
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.19.0"
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

  # Workload Identity configuration
  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = google_service_account.external_dns.email
  }

  # Enable Gateway API support
  set {
    name  = "sources[0]"
    value = "service"
  }

  set {
    name  = "sources[1]"
    value = "ingress"
  }

  set {
    name  = "sources[2]"
    value = "gateway-httproute"
  }

  depends_on = [
    google_service_account.external_dns,
    google_service_account_iam_member.external_dns_workload_identity,
    google_project_iam_member.external_dns_dns_admin
  ]
}
