# Networking Module
# Creates VPC, subnets, router, NAT, and firewall rules
module "networking" {
  source = "./modules/networking"

  project_id   = var.project_id
  region       = var.region
  cluster_name = var.cluster_name
}
