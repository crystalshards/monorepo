# Queue Module
# The Cloud Tasks queue carrying lazy documentation build requests.
#
# Nothing about the rate limits or the retry envelope is passed from here on
# purpose. Those values are argued for at length beside the resource and its
# variables, and the applied configuration is the module's defaults; an
# override here would be a second place to look for the number that decides
# what this queue can spend.
module "queue" {
  source = "./modules/queue"

  project_id = var.project_id
  region     = var.region

  depends_on = [module.project_services]
}
