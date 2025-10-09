# Loki for centralized log aggregation
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "~> 5.0"
  namespace  = "monitoring"

  timeout = 600 # 10 minutes
  wait    = true

  values = [
    yamlencode({
      loki = {
        auth_enabled = false
        commonConfig = {
          replication_factor = 1
        }
        storage = {
          type = "filesystem"
        }
        limits_config = {
          retention_period        = "168h" # 7 days
          ingestion_rate_mb       = 16
          ingestion_burst_size_mb = 32
          max_query_series        = 5000
          max_query_lookback      = "168h"
        }
        schemaConfig = {
          configs = [{
            from         = "2024-01-01"
            store        = "tsdb"
            object_store = "filesystem"
            schema       = "v13"
            index = {
              prefix = "loki_index_"
              period = "24h"
            }
          }]
        }
      }

      # Single binary deployment for cost efficiency
      deploymentMode = "SingleBinary"

      singleBinary = {
        replicas = 1
        resources = {
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "2000m"
            memory = "1Gi"
          }
        }
        persistence = {
          enabled      = true
          size         = "50Gi"
          storageClass = "standard-rwo"
        }
      }

      # Disable distributed components (not needed for single binary)
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }
      backend = {
        replicas = 0
      }

      # Gateway for query routing
      gateway = {
        enabled  = true
        replicas = 1
        resources = {
          requests = {
            cpu    = "500m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "256Mi"
          }
        }
      }

      # Monitoring integration
      monitoring = {
        serviceMonitor = {
          enabled = true
          labels = {
            release = "prometheus-operator"
          }
        }
        selfMonitoring = {
          enabled = false
          grafanaAgent = {
            installOperator = false
          }
        }
      }

      # Test configuration
      test = {
        enabled = false
      }
    })
  ]

  depends_on = [helm_release.prometheus_operator]
}
