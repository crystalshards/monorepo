output "namespace" {
  description = "The name of the agent namespace"
  value       = kubernetes_namespace.claude.metadata[0].name
}

output "service_account_name" {
  description = "The name of the agent service account"
  value       = kubernetes_service_account.claude_agent.metadata[0].name
}
