# Operators Module
# Installs cluster-wide operators (cert-manager, CNPG, Redis, OpenTelemetry, ECK, etc.)
module "operators" {
  source = "./modules/operators"

  cluster_name = module.cluster.cluster_name

  depends_on = [module.cluster]
}
