# Applications Module
# Creates namespaces, network policies, and ingress resources for apps
module "applications" {
  source = "./modules/applications"

  cluster_name = module.cluster.cluster_name
  project_id   = var.project_id
  image_tag    = var.image_tag

  depends_on = [module.ingress]
}
