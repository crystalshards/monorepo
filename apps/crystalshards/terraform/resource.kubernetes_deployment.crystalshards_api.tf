# API deployment for web server
# checkov:skip=CKV_K8S_43:Using parameterized tags for CI/CD instead of image digest
resource "kubernetes_deployment" "crystalshards_api" {
  metadata {
    name      = "crystalshards-api"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
    labels = {
      app       = "crystalshards"
      component = "api"
    }
  }

  wait_for_rollout = false  # Let Kubernetes handle rollout asynchronously

  spec {
    replicas = 2
    progress_deadline_seconds = 1200 # Allow 20 minutes for GKE Autopilot deployment

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
        annotations = {
          "crystalshards.org/image-tag" = var.image_tag
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
          name              = "api"
          image             = "us-docker.pkg.dev/${var.project_id}/crystalshards/crystalshards:${var.image_tag}"
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

          env {
            name  = "SEND_GRID_KEY"
            value = "unused"
          }

          env {
            name  = "APP_DOMAIN"
            value = "crystalshards.org"
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
            initial_delay_seconds = 120  # Increased for GKE Autopilot startup and DB connection
            period_seconds        = 10
            timeout_seconds       = 10   # Increased timeout for health check
            failure_threshold     = 6    # Allow more failures before restart
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 60   # Increased for GKE Autopilot startup and DB connection
            period_seconds        = 10   # Less frequent checks
            timeout_seconds       = 10   # Increased timeout for health check
            failure_threshold     = 6    # Allow more failures before marking unready
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
