# DNS Module - Cloud DNS managed zones
module "dns" {
  source = "./modules/dns"

  project_id = var.project_id
}
