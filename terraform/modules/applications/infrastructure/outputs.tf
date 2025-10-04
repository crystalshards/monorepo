output "namespace" {
  description = "The namespace for infrastructure"
  value       = kubernetes_namespace.infrastructure.metadata[0].name
}
