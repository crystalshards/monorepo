# CrystalBits - Newsletter/blog application
module "crystalbits" {
  source = "../../../apps/crystalbits/terraform"

  cluster_name = var.cluster_name
}
