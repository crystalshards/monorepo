# MinIO Operator for object storage
resource "helm_release" "minio_operator" {
  name       = "minio-operator"
  repository = "https://operator.min.io/"
  chart      = "operator"
  version    = "5.0.10"
  namespace  = kubernetes_namespace.infrastructure.metadata[0].name

  set {
    name  = "operator.replicaCount"
    value = "1"
  }

  # Resource limits for operator
  set {
    name  = "operator.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "operator.resources.limits.memory"
    value = "256Mi"
  }

  # Disable console for cost savings
  set {
    name  = "console.enabled"
    value = "false"
  }

  depends_on = [kubernetes_namespace.infrastructure]
}
