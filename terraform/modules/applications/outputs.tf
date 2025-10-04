output "namespaces" {
  description = "Created Kubernetes namespaces"
  value = {
    crystalshards = module.crystalshards.namespace
    crystaldocs   = module.crystaldocs.namespace
    crystalgigs   = module.crystalgigs.namespace
    crystalbits   = module.crystalbits.namespace
  }
}
