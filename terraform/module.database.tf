# Database Module
# One Cloud SQL Postgres instance, four databases, four roles, and one Secret
# Manager secret per database holding its full connection string.
#
# database_apps, not public_apps: trycrystal is a public site with no database
# by design (DESIGN.md section 1), and iterating the public list here would
# provision a fifth database nothing connects to.
module "database" {
  source = "./modules/database"

  project_id = var.project_id
  region     = var.region
  apps       = local.database_apps

  depends_on = [module.project_services]
}
