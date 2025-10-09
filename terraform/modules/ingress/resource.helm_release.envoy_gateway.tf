# Envoy Gateway for Gateway API
resource "helm_release" "envoy_gateway" {
  name       = "eg"
  repository = "oci://docker.io/envoyproxy"
  chart      = "gateway-helm"
  version    = "v1.2.4"
  namespace  = "envoy-gateway-system"

  create_namespace = true
  timeout          = 600 # 10 minutes
  wait             = true

  values = [yamlencode({
    # Configure deployment resources for GKE Autopilot
    deployment = {
      envoyGateway = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
    }

    # Enable Prometheus metrics
    config = {
      envoyGateway = {
        gateway = {
          controllerName = "gateway.envoyproxy.io/gatewayclass-controller"
        }
        provider = {
          type = "Kubernetes"
          kubernetes = {
            # Enable service metrics
            envoyService = {
              annotations = {
                "prometheus.io/scrape" = "true"
                "prometheus.io/port"   = "19001"
              }
            }
          }
        }
      }
    }
  })]

  depends_on = [var.cluster_name]
}
