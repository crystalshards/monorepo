# Applications Module
# Creates namespaces, network policies, and ingress resources for apps
module "applications" {
  source = "./modules/applications"

  cluster_name = module.cluster.cluster_name
  project_id   = var.project_id

  depends_on = [module.ingress]
}
