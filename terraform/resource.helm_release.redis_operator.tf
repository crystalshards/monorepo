# Redis Operator
resource "helm_release" "redis_operator" {
  name       = "redis-operator"
  repository = "https://ot-container-kit.github.io/helm-charts"
  chart      = "redis-operator"
  version    = "0.15.0" # Using stable version
  namespace  = kubernetes_namespace.infrastructure.metadata[0].name

  set {
    name  = "replicaCount"
    value = "1"
  }

  # Resource requests (must be less than or equal to limits)
  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  # Resource limits
  set {
    name  = "resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.limits.memory"
    value = "128Mi"
  }

  depends_on = [kubernetes_namespace.infrastructure]
}
