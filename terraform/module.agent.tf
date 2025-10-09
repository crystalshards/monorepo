module "agent" {
  source = "./modules/agent"

  depends_on = [
    module.cluster,
    module.operators
  ]
}
