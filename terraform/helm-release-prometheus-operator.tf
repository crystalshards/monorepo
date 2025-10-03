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
