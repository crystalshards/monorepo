# API deployment for web server
resource "kubernetes_deployment" "crystaldocs_api" {
  metadata {
    name      = "crystaldocs-api"
    namespace = kubernetes_namespace.crystaldocs.metadata[0].name
    labels = {
      app       = "crystaldocs"
      component = "api"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app       = "crystaldocs"
        component = "api"
      }
    }

    template {
      metadata {
        labels = {
          app       = "crystaldocs"
          component = "api"
        }
      }

      spec {
        container {
          name  = "api"
          image = "gcr.io/${var.project_id}/crystaldocs:latest"

          port {
            container_port = 3000
            name           = "http"
          }

          env {
            name  = "LUCKY_ENV"
            value = "production"
          }

          env {
            name  = "PORT"
            value = "3000"
          }

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = "crystaldocs-secrets"
                key  = "database_url"
              }
            }
          }

          env {
            name = "SECRET_KEY_BASE"
            value_from {
              secret_key_ref {
                name = "crystaldocs-secrets"
                key  = "secret_key_base"
              }
            }
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }
}
