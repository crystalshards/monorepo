# cert-manager for automatic SSL certificate management
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.14.2"
  namespace  = kubernetes_namespace.infrastructure.metadata[0].name

  timeout = 600 # 10 minutes
  wait    = true

  set {
    name  = "installCRDs"
    value = "true"
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
    value = "100m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  # Webhook resource limits
  set {
    name  = "webhook.resources.requests.cpu"
    value = "25m"
  }

  set {
    name  = "webhook.resources.requests.memory"
    value = "32Mi"
  }

  set {
    name  = "webhook.resources.limits.cpu"
    value = "50m"
  }

  set {
    name  = "webhook.resources.limits.memory"
    value = "64Mi"
  }

  # CAInjector resource limits
  set {
    name  = "cainjector.resources.requests.cpu"
    value = "25m"
  }

  set {
    name  = "cainjector.resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "cainjector.resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "cainjector.resources.limits.memory"
    value = "128Mi"
  }

  # Leader election configuration for GKE Autopilot
  # Use infrastructure namespace instead of kube-system to avoid Warden restrictions
  set {
    name  = "global.leaderElection.namespace"
    value = "infrastructure"
  }

  depends_on = [kubernetes_namespace.infrastructure]
}
