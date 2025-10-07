# API deployment for web server
resource "kubernetes_deployment" "crystalshards_api" {
  metadata {
    name      = "crystalshards-api"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
    labels = {
      app       = "crystalshards"
      component = "api"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app       = "crystalshards"
        component = "api"
      }
    }

    template {
      metadata {
        labels = {
          app       = "crystalshards"
          component = "api"
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "api"
          image = "us-docker.pkg.dev/${var.project_id}/crystalshards/crystalshards:${var.image_tag}"

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = false # Lucky needs to write tmp files
            run_as_non_root            = true
            run_as_user                = 1000
            capabilities {
              drop = ["ALL"]
            }
          }

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

          env {
            name = "MINIO_ENDPOINT"
            value_from {
              secret_key_ref {
                name = "crystalshards-secrets"
                key  = "minio_endpoint"
              }
            }
          }

          env {
            name = "MINIO_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = "crystalshards-secrets"
                key  = "minio_access_key"
              }
            }
          }

          env {
            name = "MINIO_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = "crystalshards-secrets"
                key  = "minio_secret_key"
              }
            }
          }

          env {
            name = "MINIO_REGION"
            value_from {
              secret_key_ref {
                name = "crystalshards-secrets"
                key  = "minio_region"
              }
            }
          }

          env {
            name = "MINIO_USE_SSL"
            value_from {
              secret_key_ref {
                name = "crystalshards-secrets"
                key  = "minio_use_ssl"
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
