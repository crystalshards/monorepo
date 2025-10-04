# Applications module - orchestrates all application sub-modules

# CrystalShards - Main package registry application
module "crystalshards" {
  source = "./crystalshards"

  cluster_name = var.cluster_name
}

# CrystalDocs - Documentation hosting application
module "crystaldocs" {
  source = "./crystaldocs"

  cluster_name = var.cluster_name
}

# CrystalGigs - Job board application
module "crystalgigs" {
  source = "./crystalgigs"

  cluster_name = var.cluster_name
}

# CrystalBits - Newsletter/blog application
module "crystalbits" {
  source = "./crystalbits"

  cluster_name = var.cluster_name
}

# Claude - AI agent namespace
module "claude" {
  source = "./claude"

  cluster_name = var.cluster_name
}

# Infrastructure - Shared infrastructure namespace
module "infrastructure" {
  source = "./infrastructure"

  cluster_name = var.cluster_name
}

# Network policies (applied across all namespaces)
# These should stay in the parent applications module as they span multiple namespaces
