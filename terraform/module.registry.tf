# Registry Module
# Artifact Registry repository for every application image.
module "registry" {
  source = "./modules/registry"

  project_id = var.project_id
  region     = var.region

  depends_on = [module.project_services]
}
