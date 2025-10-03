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
          container_port = 3000
        }

        env {
          name  = "ENV"
          value = "production"
        }

        env {
          name  = "PORT"
          value = "3000"
        }

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

# Make the Cloud Run service publicly accessible
resource "google_cloud_run_service_iam_member" "public" {
  location = google_cloud_run_service.simple_registry.location
  project  = google_cloud_run_service.simple_registry.project
  service  = google_cloud_run_service.simple_registry.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Enable required APIs
resource "google_project_service" "cloud_run_api" {
  service = "run.googleapis.com"

  disable_dependent_services = true
}

resource "google_project_service" "artifact_registry_api" {
  service = "artifactregistry.googleapis.com"

  disable_dependent_services = true
}

# Build and push the container image
# NOTE: This is typically done in CI/CD (GitHub Actions) but kept here for local development
resource "null_resource" "build_and_push" {
  provisioner "local-exec" {
    working_dir = "../apps/simple-registry"
    command     = <<-EOT
      # Build the Docker image
      docker build -t us-central1-docker.pkg.dev/${var.project_id}/crystalshards/simple-registry:latest .

      # Configure Docker to use gcloud as a credential helper for Artifact Registry
      gcloud auth configure-docker us-central1-docker.pkg.dev --quiet

      # Push the image to Artifact Registry
      docker push us-central1-docker.pkg.dev/${var.project_id}/crystalshards/simple-registry:latest
    EOT
  }

  # Trigger rebuild when source files change
  triggers = {
    dockerfile_hash = filemd5("../apps/simple-registry/Dockerfile")
    source_hash     = filemd5("../apps/simple-registry/src/simple-registry.cr")
    shard_hash      = filemd5("../apps/simple-registry/shard.yml")
  }

  depends_on = [google_project_service.artifact_registry_api]
}

# Output the service URL
output "simple_registry_url" {
  value       = google_cloud_run_service.simple_registry.status[0].url
  description = "URL of the deployed Crystal Shards Registry (minimal)"
}

output "simple_registry_service_name" {
  value       = google_cloud_run_service.simple_registry.name
  description = "Name of the Cloud Run service"
}