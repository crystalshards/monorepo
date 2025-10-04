# Service to expose API pods
resource "kubernetes_service" "crystalgigs" {
  metadata {
    name      = "crystalgigs"
    namespace = kubernetes_namespace.crystalgigs.metadata[0].name
    labels = {
      app = "crystalgigs"
    }
  }

  spec {
    selector = {
      app       = "crystalgigs"
      component = "api"
    }

    port {
      port        = 80
      target_port = 3000
      protocol    = "TCP"
      name        = "http"
    }

    type = "ClusterIP"
  }
}
