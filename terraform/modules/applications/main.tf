# Applications module - orchestrates all application sub-modules

# CrystalShards - Main package registry application
module "crystalshards" {
  source = "${path.module}/../../../apps/crystalshards/terraform"

  cluster_name = var.cluster_name
}

# CrystalDocs - Documentation hosting application
module "crystaldocs" {
  source = "${path.module}/../../../apps/crystaldocs/terraform"

  cluster_name = var.cluster_name
}

# CrystalGigs - Job board application
module "crystalgigs" {
  source = "${path.module}/../../../apps/crystalgigs/terraform"

  cluster_name = var.cluster_name
}

# CrystalBits - Newsletter/blog application
module "crystalbits" {
  source = "${path.module}/../../../apps/crystalbits/terraform"

  cluster_name = var.cluster_name
}

# Network policies (applied across all namespaces)
# These should stay in the parent applications module as they span multiple namespaces
