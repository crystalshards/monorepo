# Cluster Module
# Creates GKE Autopilot cluster and supporting resources
module "cluster" {
  source = "./modules/cluster"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
  network_name = module.networking.network_name
  subnet_name  = module.networking.subnet_name

  depends_on = [module.networking]
}
