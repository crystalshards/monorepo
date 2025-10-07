# CloudNativePG Operator for PostgreSQL
resource "helm_release" "cnpg" {
  name       = "cnpg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = "0.19.1"
  namespace  = kubernetes_namespace.infrastructure.metadata[0].name

  timeout = 600  # 10 minutes
  wait    = true

  set {
    name  = "replicaCount"
    value = "1"
  }

  # Resource limits
  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  depends_on = [kubernetes_namespace.infrastructure]
}
