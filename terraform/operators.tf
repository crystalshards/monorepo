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

  depends_on = [google_container_cluster.primary]
}

# CloudNativePG Operator for PostgreSQL
resource "helm_release" "cnpg" {
  name       = "cnpg"
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = "0.19.1"
  namespace  = kubernetes_namespace.infrastructure.metadata[0].name

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

# Redis Operator
resource "helm_release" "redis_operator" {
  name       = "redis-operator"
  repository = "https://ot-container-kit.github.io/helm-charts"
  chart      = "redis-operator"
  version    = "0.15.1"
  namespace  = kubernetes_namespace.infrastructure.metadata[0].name

  set {
    name  = "replicaCount"
    value = "1"
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

# Prometheus Operator for monitoring (lightweight config)
resource "helm_release" "prometheus_operator" {
  name       = "prometheus-operator"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "54.2.2"
  namespace  = "monitoring"

  create_namespace = true

  # Minimal configuration for cost optimization
  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          replicas  = 1
          retention = "7d"
          resources = {
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "100m"
              memory = "512Mi"
            }
          }
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
        }
      }
      alertmanager = {
        enabled = false
      }
      grafana = {
        enabled  = true
        replicas = 1
        resources = {
          limits = {
            cpu    = "200m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
        persistence = {
          enabled = false
        }
      }
      nodeExporter = {
        enabled = false
      }
      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  depends_on = [google_container_cluster.primary]
}

# Ingress NGINX Controller
resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.8.3"
  namespace  = "ingress-nginx"

  create_namespace = true

  set {
    name  = "controller.replicaCount"
    value = "1"
  }

  # Resource limits
  set {
    name  = "controller.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "512Mi"
  }

  # Enable autoscaling
  set {
    name  = "controller.autoscaling.enabled"
    value = "true"
  }

  set {
    name  = "controller.autoscaling.minReplicas"
    value = "1"
  }

  set {
    name  = "controller.autoscaling.maxReplicas"
    value = "5"
  }

  depends_on = [google_container_cluster.primary]
}