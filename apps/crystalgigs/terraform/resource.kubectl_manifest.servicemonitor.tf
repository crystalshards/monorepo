# ServiceMonitor for Prometheus to scrape metrics from CrystalGigs API
resource "kubectl_manifest" "crystalgigs_servicemonitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "crystalgigs-api"
      namespace = kubernetes_namespace.crystalgigs.metadata[0].name
      labels = {
        app       = "crystalgigs"
        component = "api"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "crystalgigs"
        }
      }
      endpoints = [{
        port     = "http"
        interval = "30s"
        path     = "/metrics"
      }]
    }
  })

  depends_on = [kubernetes_service.crystalgigs]
}
