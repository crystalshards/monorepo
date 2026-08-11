# The one registry for every application image.
#
# This replaces the multi region "crystalshards" repository in "us" that the
# deleted cluster module owned. It is a new repository rather than an adoption
# of that one: the old repository holds builds of apps that have changed
# underneath them, every deploy builds fresh and tags by commit SHA, and
# adopting it would mean carrying an import block forward purely to inherit a
# leftover of the architecture being removed.
#
# Images are pushed to and pulled from:
#   <region>-docker.pkg.dev/<project>/docker-images/<app>:<sha>
resource "google_artifact_registry_repository" "docker_images" {
  project       = var.project_id
  location      = var.region
  repository_id = "docker-images"
  description   = "Container images for the CrystalShards Cloud Run services and jobs"
  format        = "DOCKER"

  labels = {
    environment = "production"
    managed_by  = "terraform"
  }
}
