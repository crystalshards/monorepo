output "namespaces" {
  description = "Created Kubernetes namespaces"
  value = {
    claude         = module.claude.namespace
    crystalshards  = module.crystalshards.namespace
    crystaldocs    = module.crystaldocs.namespace
    crystalgigs    = module.crystalgigs.namespace
    crystalbits    = module.crystalbits.namespace
    infrastructure = module.infrastructure.namespace
  }
}
