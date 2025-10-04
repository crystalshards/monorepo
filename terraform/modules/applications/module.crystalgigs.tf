# CrystalGigs - Job board application
module "crystalgigs" {
  source = "../../../apps/crystalgigs/terraform"

  cluster_name = var.cluster_name
  project_id   = var.project_id
}
