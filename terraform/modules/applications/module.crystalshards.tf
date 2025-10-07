# CrystalShards - Main package registry application
module "crystalshards" {
  source = "../../../apps/crystalshards/terraform"

  cluster_name = var.cluster_name
  project_id   = var.project_id
  image_tag    = var.image_tag
}
