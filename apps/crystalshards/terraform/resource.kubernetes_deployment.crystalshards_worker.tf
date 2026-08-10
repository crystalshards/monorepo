# Worker deployment for background job processing
# checkov:skip=CKV_K8S_43:Using parameterized tags for CI/CD instead of image digest
resource "kubernetes_deployment" "crystalshards_worker" {
  metadata {
    name      = "crystalshards-worker"
    namespace = kubernetes_namespace.crystalshards.metadata[0].name
    labels = {
      app       = "crystalshards"
      component = "worker"
    }
  }

  wait_for_rollout = false # Let Kubernetes handle rollout asynchronously

  spec {
    replicas                  = 2    # Start with 2 worker pods
    progress_deadline_seconds = 1200 # Allow 20 minutes for GKE Autopilot deployment

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
        annotations = {
          "crystalshards.org/image-tag"   = var.image_tag
          "crystalshards.org/secret-hash" = sha256(jsonencode(kubernetes_secret.crystalshards_secrets.data))
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

          env {
            name  = "SEND_GRID_KEY"
            value = "unused"
          }

          env {
            name  = "APP_DOMAIN"
            value = "crystalshards.org"
          }

          # Documentation build sandbox configuration. None of these are
          # secrets, so plain values are used. The untrusted `crystal docs`
          # step runs as a Job in the isolated docs-sandbox namespace; the
          # trusted fetch/upload steps move data through MinIO.
          env {
            name  = "DOCS_SANDBOX"
            value = "kubernetes"
          }

          env {
            name  = "DOCS_SANDBOX_NAMESPACE"
            value = kubernetes_namespace.docs_sandbox.metadata[0].name
          }

          env {
            name  = "DOCS_SANDBOX_IMAGE"
            value = var.docs_sandbox_image
          }

          env {
            name  = "DOCS_SANDBOX_TIMEOUT_SECONDS"
            value = tostring(var.docs_sandbox_timeout_seconds)
          }

          env {
            name  = "DOCS_SANDBOX_MEMORY"
            value = var.docs_sandbox_memory
          }

          env {
            name  = "DOCS_SANDBOX_CPUS"
            value = var.docs_sandbox_cpus
          }

          env {
            name  = "DOCS_SANDBOX_PIDS"
            value = tostring(var.docs_sandbox_pids)
          }

          # Optional RuntimeClass (for example gvisor). Empty string means the
          # cluster default runtime. NOTE: coalesce() cannot be used here; it
          # rejects empty-string arguments and would fail at plan time when the
          # variable is null.
          env {
            name  = "DOCS_SANDBOX_RUNTIME_CLASS"
            value = var.docs_sandbox_runtime_class == null ? "" : var.docs_sandbox_runtime_class
          }

          env {
            name  = "DOCS_SANDBOX_SCRATCH_PREFIX"
            value = var.docs_sandbox_scratch_prefix
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
            initial_delay_seconds = 120 # Increased for GKE Autopilot startup and DB connection
            period_seconds        = 30
            failure_threshold     = 5 # Allow more failures before restart
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
