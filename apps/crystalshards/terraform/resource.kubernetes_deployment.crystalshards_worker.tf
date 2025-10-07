# Worker deployment for background job processing
resource "kubernetes_deployment" "crystalshards_worker" {
  metadata {
    name      = "crystalshards-worker"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
    labels = {
      app       = "crystalshards"
      component = "worker"
    }
  }

  spec {
    replicas = 2 # Start with 2 worker pods

    selector {
      match_labels = {
        app       = "crystalshards"
        component = "worker"
      }
    }

    template {
      metadata {
        labels = {
          app       = "crystalshards"
          component = "worker"
        }
      }

      spec {
        container {
          name  = "worker"
          image = "us-docker.pkg.dev/${var.project_id}/crystalshards/crystalshards-worker:latest"

          env {
            name  = "LUCKY_ENV"
            value = "production"
          }

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = "crystalshards-secrets"
                key  = "database_url"
              }
            }
          }

          env {
            name = "REDIS_URL"
            value_from {
              secret_key_ref {
                name = "crystalshards-secrets"
                key  = "redis_url"
              }
            }
          }

          env {
            name = "SECRET_KEY_BASE"
            value_from {
              secret_key_ref {
                name = "crystalshards-secrets"
                key  = "secret_key_base"
              }
            }
          }

          # Resource limits for Autopilot
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

          # Liveness probe - worker should stay alive
          liveness_probe {
            exec {
              command = ["pgrep", "-f", "worker"]
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }
        }
      }
    }
  }
}
