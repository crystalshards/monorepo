# Edge: one global external Application Load Balancer serving all eight public
# hostnames, with a serverless NEG per Cloud Run service and Google managed
# certificates.
module "edge" {
  source = "./modules/edge"

  project_id    = var.project_id
  region        = module.services.region
  sites         = local.sites
  service_names = module.services.service_names

  # Compute and Certificate Manager APIs are enabled in module.project_services.
  # This module deliberately does not declare its own google_project_service:
  # two declarations of the same API in one project is a duplicate resource.
  depends_on = [module.project_services]
}
