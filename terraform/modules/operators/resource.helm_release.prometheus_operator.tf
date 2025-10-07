# Prometheus Operator for monitoring (lightweight config)
resource "helm_release" "prometheus_operator" {
  name       = "prometheus-operator"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "54.2.2"
  namespace  = "monitoring"

  create_namespace = true

  # GKE Autopilot-compatible configuration
  # Autopilot restricts access to kube-system namespace and control plane components
  values = [
    yamlencode({
      # Disable components that try to access kube-system or control plane
      defaultRules = {
        create = true
        rules = {
          kubeScheduler            = false
          kubeControllerManager   = false
          kubeProxy               = false
          kubeApiserverSlos       = false
        }
      }

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

      # Disable node exporter for GKE Autopilot
      nodeExporter = {
        enabled = false
      }

      # Keep kube-state-metrics for basic cluster metrics
      kubeStateMetrics = {
        enabled = true
      }

      # Disable all control plane component monitoring for GKE Autopilot
      kubeApiServer = {
        enabled = false
      }

      kubeControllerManager = {
        enabled = false
      }

      kubeScheduler = {
        enabled = false
      }

      kubeProxy = {
        enabled = false
      }

      kubeEtcd = {
        enabled = false
      }

      # Disable CoreDNS monitoring to avoid kube-system access
      coreDns = {
        enabled = false
      }

      # Disable kubeDns monitoring
      kubeDns = {
        enabled = false
      }
    })
  ]
}
