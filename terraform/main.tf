# Main Terraform configuration that orchestrates all modules

# Networking Module
# Creates VPC, subnets, router, NAT, and firewall rules
module "networking" {
  source = "./modules/networking"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
}

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

# Operators Module
# Installs cluster-wide operators (cert-manager, CNPG, Redis, etc.)
module "operators" {
  source = "./modules/operators"

  cluster_name = module.cluster.cluster_name

  depends_on = [module.cluster]
}

# Ingress Module
# Installs nginx-ingress controller and external-dns
module "ingress" {
  source = "./modules/ingress"

  cluster_name = module.cluster.cluster_name
  project_id   = var.project_id

  depends_on = [module.operators]
}

# Applications Module
# Creates namespaces, network policies, and ingress resources for apps
module "applications" {
  source = "./modules/applications"

  cluster_name = module.cluster.cluster_name
  project_id   = var.project_id

  depends_on = [module.ingress]
}
