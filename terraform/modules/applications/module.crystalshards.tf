# CrystalShards - Main package registry application
module "crystalshards" {
  source = "../../../apps/crystalshards/terraform"

  cluster_name           = var.cluster_name
  project_id             = var.project_id
  image_tag              = var.image_tag
  postgres_backup_bucket = var.postgres_backup_bucket
  redis_backup_bucket    = var.redis_backup_bucket
  minio_backup_bucket    = var.minio_backup_bucket
}
