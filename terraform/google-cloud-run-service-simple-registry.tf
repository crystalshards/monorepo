# Simple deployment for minimal Crystal Shards Registry
# Focus: Get something basic deployed and web-accessible first

# Google Cloud Run service for simple deployment
resource "google_cloud_run_service" "simple_registry" {
  name     = "simple-crystal-registry"
  location = var.region

  template {
    spec {
      containers {
        image = "us-central1-docker.pkg.dev/${var.project_id}/crystalshards/simple-registry:latest"

        ports {
          container_port = 8080
        }

        env {
          name  = "ENV"
          value = "production"
        }

        # PORT is automatically set by Cloud Run (reserved)
        # App should use $PORT environment variable

        resources {
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      # Allow up to 100 concurrent requests per container
      container_concurrency = 100

      # Scale to zero when idle
      timeout_seconds = 300
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale"         = "0"
        "autoscaling.knative.dev/maxScale"         = "10"
        "run.googleapis.com/execution-environment" = "gen2"
        "run.googleapis.com/cpu-throttling"        = "true"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [google_project_service.cloud_run_api]
}
