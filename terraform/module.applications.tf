# Applications Module
# Creates namespaces, network policies, and ingress resources for apps
module "applications" {
  source = "./modules/applications"

  cluster_name = module.cluster.cluster_name
  project_id   = var.project_id
  image_tag    = var.image_tag

  # CrystalBits secrets
  crystalbits_resend_key = var.crystalbits_resend_key

  # CrystalGigs secrets
  crystalgigs_resend_key             = var.crystalgigs_resend_key
  crystalgigs_stripe_secret_key      = var.crystalgigs_stripe_secret_key
  crystalgigs_stripe_publishable_key = var.crystalgigs_stripe_publishable_key

  depends_on = [module.ingress]
}
