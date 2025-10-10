# Database initialization job - runs db.create and db.migrate
resource "kubernetes_job" "crystalgigs_db_init" {
  metadata {
    name      = "crystalgigs-db-init"
    namespace = kubernetes_namespace.crystalgigs.metadata[0].name
    labels = {
      app       = "crystalgigs"
      component = "db-init"
    }
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
    update = "5m"
  }

  spec {
    backoff_limit = 3
    ttl_seconds_after_finished = 600  # Clean up after 10 minutes

    template {
      metadata {
        labels = {
          app       = "crystalgigs"
          component = "db-init"
        }
      }

      spec {
        restart_policy = "OnFailure"

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        # Init container to wait for PostgreSQL to be ready
        init_container {
          name  = "wait-for-postgres"
          image = "postgres:15-alpine"

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 70  # postgres user in alpine
            capabilities {
              drop = ["ALL"]
            }
          }

          command = ["sh", "-c"]
          args = [
            <<-EOF
            echo "Waiting for PostgreSQL to be ready..."
            until pg_isready -h crystalgigs-postgres-rw -p 5432 -U app; do
              echo "PostgreSQL is unavailable - sleeping"
              sleep 2
            done
            echo "PostgreSQL is ready!"
            EOF
          ]

          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.crystalgigs_secrets.metadata[0].name
                key  = "database_url"
              }
            }
          }
        }

        container {
          name  = "db-init"
          image = "us-docker.pkg.dev/${var.project_id}/crystalshards/crystalgigs:${var.image_tag}"

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

          command = ["sh", "-c"]
          args = [
            <<-EOF
            echo "Initializing database..."
            lucky db.create || echo "Database already exists"
            echo "Running migrations..."
            lucky db.migrate
            echo "Database initialization complete!"
            EOF
          ]

          env {
            name  = "LUCKY_ENV"
            value = "production"
          }

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.crystalgigs_secrets.metadata[0].name
                key  = "database_url"
              }
            }
          }

          env {
            name = "SECRET_KEY_BASE"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.crystalgigs_secrets.metadata[0].name
                key  = "secret_key_base"
              }
            }
          }

          env {
            name = "RESEND_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.crystalgigs_secrets.metadata[0].name
                key  = "resend_api_key"
              }
            }
          }

          env {
            name = "STRIPE_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.crystalgigs_secrets.metadata[0].name
                key  = "stripe_secret_key"
              }
            }
          }

          env {
            name = "STRIPE_PUBLISHABLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.crystalgigs_secrets.metadata[0].name
                key  = "stripe_publishable_key"
              }
            }
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [
    kubectl_manifest.crystalgigs_postgres,
    kubernetes_secret.crystalgigs_secrets
  ]

  lifecycle {
    replace_triggered_by = [
      kubernetes_secret.crystalgigs_secrets.id
    ]
  }
}
