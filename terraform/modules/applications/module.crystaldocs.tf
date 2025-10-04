# CrystalDocs - Documentation hosting application
module "crystaldocs" {
  source = "../../../apps/crystaldocs/terraform"

  cluster_name = var.cluster_name
  project_id   = var.project_id
}
