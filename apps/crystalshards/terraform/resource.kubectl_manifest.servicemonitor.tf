# ServiceMonitor for Prometheus to scrape metrics from CrystalShards API
resource "kubectl_manifest" "crystalshards_servicemonitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "crystalshards-api"
      namespace = kubernetes_namespace.crystalshards.metadata[0].name
      labels = {
        app       = "crystalshards"
        component = "api"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "crystalshards"
        }
      }
      endpoints = [{
        port     = "http"
        interval = "30s"
        path     = "/metrics"
      }]
    }
  })

  depends_on = [kubernetes_service.crystalshards]
}
