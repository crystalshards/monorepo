# Project Services Module
# Enables every GCP API this project depends on, in one place.
#
# It is declared first and everything else depends on it, so an apply against a
# clean project cannot fail with "API not enabled" for something a later module
# assumed was already on. It also owns artifactregistry.googleapis.com, which
# previously lived in the GKE cluster module with disable_dependent_services
# set: leaving it there would have meant the cluster teardown proposing to
# disable the API the new image repository runs on.
module "project_services" {
  source = "./modules/project_services"

  project_id = var.project_id
}
