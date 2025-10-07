# API deployment for web server
resource "kubernetes_deployment" "crystalbits_api" {
  metadata {
    name      = "crystalbits-api"
    namespace = kubernetes_namespace.crystalbits.metadata[0].name
    labels = {
      app       = "crystalbits"
      component = "api"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app       = "crystalbits"
        component = "api"
      }
    }

    template {
      metadata {
        labels = {
          app       = "crystalbits"
          component = "api"
        }
      }

      spec {
        container {
          name  = "api"
          image = "us-docker.pkg.dev/${var.project_id}/crystalshards/crystalbits:latest"

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
                name = "crystalbits-secrets"
                key  = "database_url"
              }
            }
          }

          env {
            name = "SECRET_KEY_BASE"
            value_from {
              secret_key_ref {
                name = "crystalbits-secrets"
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
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }
        }
      }
    }
  }
}
