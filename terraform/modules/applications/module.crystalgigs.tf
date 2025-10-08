# CrystalGigs - Job board application
module "crystalgigs" {
  source = "../../../apps/crystalgigs/terraform"

  cluster_name           = var.cluster_name
  project_id             = var.project_id
  image_tag              = var.image_tag
  resend_key             = var.crystalgigs_resend_key
  stripe_secret_key      = var.crystalgigs_stripe_secret_key
  stripe_publishable_key = var.crystalgigs_stripe_publishable_key
}
