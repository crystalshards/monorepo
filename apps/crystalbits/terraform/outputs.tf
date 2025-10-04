output "namespace" {
  description = "The namespace for crystalbits"
  value       = kubernetes_namespace.crystalbits.metadata[0].name
}
