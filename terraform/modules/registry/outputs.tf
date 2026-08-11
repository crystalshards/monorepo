output "repository_id" {
  description = "Artifact Registry repository ID"
  value       = google_artifact_registry_repository.docker_images.repository_id
}

output "location" {
  description = "Region the repository lives in"
  value       = google_artifact_registry_repository.docker_images.location
}

output "repository_url" {
  description = "Registry path images are tagged against, without a trailing slash"
  value       = "${google_artifact_registry_repository.docker_images.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker_images.repository_id}"
}
