resource "google_artifact_registry_repository" "docker_images" {
  location      = "us"
  repository_id = "crystalshards"
  description   = "Docker images for CrystalShards applications"
  format        = "DOCKER"

  labels = {
    environment = "production"
    managed_by  = "terraform"
  }
}
