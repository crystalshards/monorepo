# Database Module
# One Cloud SQL Postgres instance, four databases, four roles, and one Secret
# Manager secret per database holding its full connection string.
module "database" {
  source = "./modules/database"

  project_id = var.project_id
  region     = var.region
  apps       = local.apps

  depends_on = [module.project_services]
}
