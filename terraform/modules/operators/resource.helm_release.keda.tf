# KEDA Autoscaler
resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "2.12.1"
  namespace  = "keda-system"

  create_namespace = true

  set {
    name  = "operator.replicaCount"
    value = "1"
  }

  set {
    name  = "metricsServer.replicaCount"
    value = "1"
  }

  set {
    name  = "webhooks.replicaCount"
    value = "1"
  }

  # Resource limits for cost optimization
  set {
    name  = "resources.operator.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.operator.limits.memory"
    value = "128Mi"
  }
}
