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
