# Traefik Ingress Controller with OpenTelemetry
resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = "~> 31.0"
  namespace  = "traefik-system"

  create_namespace = true
  timeout          = 600 # 10 minutes
  wait             = true

  values = [yamlencode({
    # Service configuration
    service = {
      type = "LoadBalancer"
      annotations = {
        "cloud.google.com/load-balancer-type" = "External"
      }
    }

    # Enable Traefik Dashboard (for debugging)
    ingressRoute = {
      dashboard = {
        enabled = false # Set to true if you want the dashboard exposed
      }
    }

    # Ports configuration
    ports = {
      web = {
        port        = 80
        exposedPort = 80
        protocol    = "TCP"
      }
      websecure = {
        port        = 443
        exposedPort = 443
        protocol    = "TCP"
        tls = {
          enabled = true
        }
      }
    }

    # Access logs and provider configuration
    additionalArguments = [
      "--accesslog=true",
      "--accesslog.format=json",
      "--providers.kubernetesingress.publishedservice.enabled=true"
    ]

    # Resource limits for Autopilot
    resources = {
      requests = {
        cpu    = "100m"
        memory = "128Mi"
      }
      limits = {
        cpu    = "1000m"
        memory = "512Mi"
      }
    }

    # Pod annotations for autoscaling
    podAnnotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "9100"
    }

    # Autoscaling with KEDA
    autoscaling = {
      enabled = false # Will use KEDA ScaledObject instead
    }
  })]

  depends_on = [var.cluster_name]
}
