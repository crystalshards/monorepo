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
        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = "worker"
          image             = "us-docker.pkg.dev/${var.project_id}/crystalshards/crystalshards-worker:${var.image_tag}"
          image_pull_policy = "Always"

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 1000
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

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

        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}
