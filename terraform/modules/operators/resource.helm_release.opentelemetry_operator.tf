# OpenTelemetry Operator
resource "helm_release" "opentelemetry_operator" {
  name       = "opentelemetry-operator"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-operator"
  version    = "~> 0.72"
  namespace  = "opentelemetry-system"

  create_namespace = true

  values = [yamlencode({
    manager = {
      resources = {
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
      }
    }

    # Enable auto-instrumentation
    autoInstrumentation = {
      enabled = true
    }
  })]
}

# OpenTelemetry Collector instance
resource "helm_release" "opentelemetry_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "~> 0.107"
  namespace  = "observability"

  create_namespace = true

  values = [yamlencode({
    mode = "deployment"

    config = {
      receivers = {
        otlp = {
          protocols = {
            grpc = {
              endpoint = "0.0.0.0:4317"
            }
            http = {
              endpoint = "0.0.0.0:4318"
            }
          }
        }
      }

      processors = {
        batch = {}
        memory_limiter = {
          check_interval  = "1s"
          limit_mib       = 400
          spike_limit_mib = 100
        }
      }

      exporters = {
        # Export to Elastic APM
        otlp = {
          endpoint = "elastic-apm.elastic-system:8200"
          tls = {
            insecure = true
          }
        }
        # Also export to logging for debugging
        logging = {
          loglevel = "info"
        }
      }

      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "batch"]
            exporters  = ["otlp", "logging"]
          }
          metrics = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "batch"]
            exporters  = ["otlp", "logging"]
          }
          logs = {
            receivers  = ["otlp"]
            processors = ["memory_limiter", "batch"]
            exporters  = ["otlp", "logging"]
          }
        }
      }
    }

    resources = {
      limits = {
        cpu    = "500m"
        memory = "512Mi"
      }
      requests = {
        cpu    = "100m"
        memory = "256Mi"
      }
    }
  })]

  depends_on = [helm_release.opentelemetry_operator]
}
