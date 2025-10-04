output "namespace" {
  description = "The namespace for crystaldocs"
  value       = kubernetes_namespace.crystaldocs.metadata[0].name
}
