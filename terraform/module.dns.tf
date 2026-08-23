# Cloud DNS: the five managed zones, plus an A record for each of the ten
# public hostnames pointing at the load balancer in module.edge.
module "dns" {
  source = "./modules/dns"

  project_id       = var.project_id
  sites            = local.sites
  load_balancer_ip = module.edge.load_balancer_ip
}
