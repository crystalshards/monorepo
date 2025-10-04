output "namespace" {
  description = "The namespace for crystalshards"
  value       = kubernetes_namespace.crystalshards.metadata[0].name
}
