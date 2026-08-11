# Queue Module
# The Cloud Tasks queue carrying lazy documentation build requests.
module "queue" {
  source = "./modules/queue"

  project_id = var.project_id
  region     = var.region

  depends_on = [module.project_services]
}
