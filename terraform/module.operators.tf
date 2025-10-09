# Operators Module
# Installs cluster-wide operators (cert-manager, CNPG, Redis, OpenTelemetry, ECK, etc.)
module "operators" {
  source = "./modules/operators"

  cluster_name           = module.cluster.cluster_name
  postgres_backup_bucket = module.cluster.postgres_backup_bucket
  redis_backup_bucket    = module.cluster.redis_backup_bucket
  minio_backup_bucket    = module.cluster.minio_backup_bucket

  depends_on = [module.cluster]
}
