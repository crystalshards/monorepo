# MinIO Operator for object storage
resource "helm_release" "minio_operator" {
  name       = "minio-operator"
  repository = "https://operator.min.io/"
  chart      = "operator"
  version    = "5.0.10"
  namespace  = kubernetes_namespace.infrastructure.metadata[0].name

  timeout = 600  # 10 minutes
  wait    = true

  set {
    name  = "operator.replicaCount"
    value = "1"
  }

  # Resource limits for operator - GKE Autopilot requires 500m minimum CPU for pod anti-affinity
  set {
    name  = "operator.resources.requests.cpu"
    value = "500m"
  }

  set {
    name  = "operator.resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "operator.resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "operator.resources.limits.memory"
    value = "1Gi"
  }

  # Disable console for cost savings
  set {
    name  = "console.enabled"
    value = "false"
  }

  depends_on = [kubernetes_namespace.infrastructure]
}
