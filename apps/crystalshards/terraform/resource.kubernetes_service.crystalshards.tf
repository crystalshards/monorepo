# Service to expose API pods
resource "kubernetes_service" "crystalshards" {
  metadata {
    name      = "crystalshards"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
    labels = {
      app = "crystalshards"
    }
  }

  spec {
    selector = {
      app       = "crystalshards"
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
