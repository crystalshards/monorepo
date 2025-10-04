# Applications module - orchestrates all application sub-modules

# CrystalShards - Main package registry application
module "crystalshards" {
  source = "../../../apps/crystalshards/terraform"

  cluster_name = var.cluster_name
  project_id   = var.project_id
}

# CrystalDocs - Documentation hosting application
module "crystaldocs" {
  source = "../../../apps/crystaldocs/terraform"

  cluster_name = var.cluster_name
}

# CrystalGigs - Job board application
module "crystalgigs" {
  source = "../../../apps/crystalgigs/terraform"

  cluster_name = var.cluster_name
}

# CrystalBits - Newsletter/blog application
module "crystalbits" {
  source = "../../../apps/crystalbits/terraform"

  cluster_name = var.cluster_name
}

# Network policies (applied across all namespaces)
# These should stay in the parent applications module as they span multiple namespaces
