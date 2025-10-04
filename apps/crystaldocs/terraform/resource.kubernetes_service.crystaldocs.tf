# Service to expose API pods
resource "kubernetes_service" "crystaldocs" {
  metadata {
    name      = "crystaldocs"
    namespace = kubernetes_namespace.crystaldocs.metadata[0].name
    labels = {
      app = "crystaldocs"
    }
  }

  spec {
    selector = {
      app       = "crystaldocs"
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
