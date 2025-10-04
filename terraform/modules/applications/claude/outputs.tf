output "namespace" {
  description = "The namespace for claude"
  value       = kubernetes_namespace.claude.metadata[0].name
}
