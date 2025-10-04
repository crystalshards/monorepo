output "namespace" {
  description = "The namespace for crystalgigs"
  value       = kubernetes_namespace.crystalgigs.metadata[0].name
}
