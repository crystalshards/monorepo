# Service to expose API pods
resource "kubernetes_service" "crystalbits" {
  metadata {
    name      = "crystalbits"
    namespace = kubernetes_namespace.crystalbits.metadata[0].name
    labels = {
      app = "crystalbits"
    }
  }

  spec {
    selector = {
      app       = "crystalbits"
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
