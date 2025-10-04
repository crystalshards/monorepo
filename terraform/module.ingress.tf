# Ingress Module
# Installs Traefik ingress controller and external-dns
module "ingress" {
  source = "./modules/ingress"

  cluster_name = module.cluster.cluster_name
  project_id   = var.project_id

  depends_on = [module.operators]
}
