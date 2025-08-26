# Simple Terraform configuration for Cloud Run deployment only
# This is a focused configuration for getting the simple app deployed

terraform {
  required_version = ">= 1.0"

  cloud {
    organization = "crystalshards"
    workspaces {
      name = "crystalshards-simple"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.84"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "cloud_run_api" {
  service = "run.googleapis.com"

  disable_dependent_services = true
}

resource "google_project_service" "container_registry_api" {
  service = "containerregistry.googleapis.com"

  disable_dependent_services = true
}

# Build and push the container image
resource "null_resource" "build_and_push" {
  provisioner "local-exec" {
    working_dir = "../apps/simple-registry"
    command     = <<-EOT
      # Build the Docker image
      docker build -t gcr.io/${var.project_id}/simple-registry:latest .
      
      # Configure Docker to use gcloud as a credential helper
      gcloud auth configure-docker --quiet
      
      # Push the image to Google Container Registry
      docker push gcr.io/${var.project_id}/simple-registry:latest
    EOT
  }

  # Trigger rebuild when source files change
  triggers = {
    dockerfile_hash = filemd5("../apps/simple-registry/Dockerfile")
    source_hash     = filemd5("../apps/simple-registry/src/simple-registry.cr")
    shard_hash      = filemd5("../apps/simple-registry/shard.yml")
  }

  depends_on = [google_project_service.container_registry_api]
}

# Google Cloud Run service for simple deployment
resource "google_cloud_run_service" "simple_registry" {
  name     = "simple-crystal-registry"
  location = var.region

  template {
    spec {
      containers {
        image = "gcr.io/${var.project_id}/simple-registry:latest"

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

  depends_on = [google_project_service.cloud_run_api, null_resource.build_and_push]
}

# Make the Cloud Run service publicly accessible
resource "google_cloud_run_service_iam_member" "public" {
  location = google_cloud_run_service.simple_registry.location
  project  = google_cloud_run_service.simple_registry.project
  service  = google_cloud_run_service.simple_registry.name
  role     = "roles/run.invoker"
  member   = "allUsers"
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