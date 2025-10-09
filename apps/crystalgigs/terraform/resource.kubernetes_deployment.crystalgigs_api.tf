# API deployment for web server
# checkov:skip=CKV_K8S_43:Using parameterized tags for CI/CD instead of image digest
resource "kubernetes_deployment" "crystalgigs_api" {
  metadata {
    name      = "crystalgigs-api"
    namespace = kubernetes_namespace.crystalgigs.metadata[0].name
    labels = {
      app       = "crystalgigs"
      component = "api"
    }
  }

  spec {
    replicas = 2
    progress_deadline_seconds = 1200 # Allow 20 minutes for GKE Autopilot deployment

    selector {
      match_labels = {
        app       = "crystalgigs"
        component = "api"
      }
    }

    template {
      metadata {
        labels = {
          app       = "crystalgigs"
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
          name              = "api"
          image             = "us-docker.pkg.dev/${var.project_id}/crystalshards/crystalgigs:${var.image_tag}"
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
                name = "crystalgigs-secrets"
                key  = "database_url"
              }
            }
          }

          env {
            name = "SECRET_KEY_BASE"
            value_from {
              secret_key_ref {
                name = "crystalgigs-secrets"
                key  = "secret_key_base"
              }
            }
          }

          env {
            name  = "SEND_GRID_KEY"
            value = "unused"
          }

          env {
            name  = "APP_DOMAIN"
            value = "crystalgigs.com"
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
            initial_delay_seconds = 60  # Increased for GKE Autopilot startup
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 30  # Increased for GKE Autopilot startup
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
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
