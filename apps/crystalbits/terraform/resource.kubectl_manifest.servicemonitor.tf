# ServiceMonitor for Prometheus to scrape metrics from CrystalBits API
resource "kubectl_manifest" "crystalbits_servicemonitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "crystalbits-api"
      namespace = kubernetes_namespace.crystalbits.metadata[0].name
      labels = {
        app       = "crystalbits"
        component = "api"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "crystalbits"
        }
      }
      endpoints = [{
        port     = "http"
        interval = "30s"
        path     = "/metrics"
      }]
    }
  })

  depends_on = [kubernetes_service.crystalbits]
}
