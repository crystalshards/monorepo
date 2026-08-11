# Storage Module
# The documentation and package buckets.
module "storage" {
  source = "./modules/storage"

  project_id = var.project_id
  region     = var.region

  depends_on = [module.project_services]
}
