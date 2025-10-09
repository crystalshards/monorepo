# ServiceMonitor for Prometheus to scrape metrics from CrystalDocs API
resource "kubectl_manifest" "crystaldocs_servicemonitor" {
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "crystaldocs-api"
      namespace = kubernetes_namespace.crystaldocs.metadata[0].name
      labels = {
        app       = "crystaldocs"
        component = "api"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "crystaldocs"
        }
      }
      endpoints = [{
        port     = "http"
        interval = "30s"
        path     = "/metrics"
      }]
    }
  })

  depends_on = [kubernetes_service.crystaldocs]
}
