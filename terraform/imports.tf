# Import blocks for existing resources
# These will import existing GCP resources into Terraform state

# Import existing Artifact Registry repository
# Created manually before Terraform was configured
import {
  to = module.cluster.google_artifact_registry_repository.docker_images
  id = "projects/crystalshards-org/locations/us/repositories/crystalshards"
}
